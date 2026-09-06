import type { PoolClient } from "pg";

/**
 * Acesso à fila de ingestão (`job.fila`).
 *
 * Duas coisas moldam este módulo:
 *
 * 1. **O schema `job` está fora do PostgREST** por decisão (nenhuma tela vê a
 *    fila), então o worker fala com o Postgres direto, não pelo cliente
 *    Supabase. A conexão assume `service_role` — os privilégios são os mesmos
 *    que a aplicação tem, verificados pelo banco, não por convenção.
 * 2. **Enfileirar é sempre `job.enfileirar`** (ADR-0025, ADR-0026). `insert`
 *    direto em `job.fila` não deve existir em lugar nenhum: é a função que
 *    aplica a chave de idempotência contra o índice único parcial. Com `insert`
 *    solto, dois caminhos pedindo o mesmo trabalho viram dois jobs.
 */

export type TipoDeJob =
  | "hash_dedupe"
  | "extracao_nativa"
  | "ocr_pagina"
  | "chunking"
  | "embedding_lote"
  | "classificacao";

export interface Job {
  id: string;
  tipo: TipoDeJob;
  payload: Record<string, unknown>;
  tentativas: number;
  maxTentativas: number;
}

/** Erro que não adianta repetir: PDF com senha, arquivo corrompido, objeto sumido. */
export class ErroPermanente extends Error {
  readonly permanente = true;
}

/**
 * Toma o próximo job pronto.
 *
 * `for update skip locked` é o mecanismo previsto no ADR-0007: dois workers
 * nunca pegam a mesma linha, e nenhum espera o outro. A transação é curta de
 * propósito — o trabalho pesado acontece **fora** dela.
 */
export async function tomaJob(db: PoolClient): Promise<Job | null> {
  const { rows } = await db.query(
    `update job.fila f
        set status = 'processando', iniciado_em = now(), tentativas = tentativas + 1
      where f.id = (
        select id from job.fila
         where status = 'pendente' and disponivel_em <= now()
         order by prioridade, disponivel_em
         for update skip locked
         limit 1)
    returning f.id, f.tipo, f.payload, f.tentativas, f.max_tentativas`,
  );
  if (rows.length === 0) return null;
  const linha = rows[0];
  return {
    id: String(linha.id),
    tipo: linha.tipo as TipoDeJob,
    payload: linha.payload as Record<string, unknown>,
    tentativas: linha.tentativas,
    maxTentativas: linha.max_tentativas,
  };
}

export async function concluiJob(db: PoolClient, id: string): Promise<void> {
  await db.query(
    `update job.fila set status = 'concluido', concluido_em = now(), erro = null where id = $1`,
    [id],
  );
}

/**
 * Marca a falha e decide entre tentar de novo e desistir.
 *
 * - **Erro permanente não tenta de novo.** Repetir cinco vezes um PDF corrompido
 *   só atrasa a única coisa que resolve, que é uma pessoa olhar.
 * - **Erro desconhecido conta como transitório** — desconhecido costuma ser rede.
 * - **Morrer escreve no documento, na mesma transação.** A fila está fora do
 *   PostgREST: se o job morre em silêncio, o documento fica num estado
 *   intermediário para sempre e quem subiu o arquivo nunca fica sabendo. É a
 *   mesma classe de falha do E2, por outro caminho.
 */
export async function falhaJob(
  db: PoolClient,
  job: Job,
  erro: unknown,
  documentoId?: string,
): Promise<"retentar" | "morto"> {
  const mensagem = erro instanceof Error ? erro.message : String(erro);
  const permanente = erro instanceof ErroPermanente;
  const acabaram = job.tentativas >= job.maxTentativas;

  if (permanente || acabaram) {
    await db.query("begin");
    try {
      await db.query(
        `update job.fila set status = 'morto', concluido_em = now(), erro = $2 where id = $1`,
        [job.id, mensagem],
      );
      if (documentoId) {
        await db.query(
          `update public.documentos set status = 'erro', erro_detalhe = $2 where id = $1`,
          [documentoId, mensagem],
        );
      }
      await db.query("commit");
    } catch (falha) {
      await db.query("rollback");
      throw falha;
    }
    return "morto";
  }

  // Backoff exponencial com teto de uma hora (ADR-0025 §4).
  await db.query(
    `update job.fila
        set status = 'pendente',
            erro = $2,
            disponivel_em = now() + least(interval '30 seconds' * power(2, tentativas), interval '1 hour')
      where id = $1`,
    [job.id, mensagem],
  );
  return "retentar";
}

/**
 * Devolve à fila o job cujo worker morreu segurando o lease.
 *
 * Roda no arranque e a cada ciclo de polling, porque o caso que importa é
 * exatamente "o worker morreu e voltou". Sem isso, um crash engole o documento
 * em silêncio — a falha que o comentário da tabela já avisava em F0.
 */
export async function varreLeasesExpirados(
  db: PoolClient,
  minutos = 15,
): Promise<number> {
  const { rowCount } = await db.query(
    `update job.fila
        set status = 'pendente', iniciado_em = null
      where status = 'processando'
        and iniciado_em < now() - ($1 || ' minutes')::interval`,
    [String(minutos)],
  );
  return rowCount ?? 0;
}

export interface PedidoDeJob {
  tipo: TipoDeJob;
  /** Sempre obrigatório: é a chave que o índice da fila e a sentinela leem. */
  documentoId: string;
  payload?: Record<string, unknown>;
  /** `<tipo>:<documento|sha256>:v<versao>[:<pagina|lote>]` (ADR-0025 §2). */
  chaveIdempotencia: string;
  prioridade?: number;
}

/**
 * Enfileira pela função do banco — nunca por `insert` direto.
 *
 * Quando chamada **dentro da transação que escreve o resultado do estágio
 * anterior**, o enfileiramento commita junto: não existe o estado "escreveu e
 * não enfileirou". É a vantagem concreta de a fila morar no mesmo Postgres, e
 * era a que estava sobrando sem uso.
 */
export async function enfileira(
  db: PoolClient,
  pedido: PedidoDeJob,
): Promise<string | null> {
  const { rows } = await db.query<{ enfileirar: string | null }>(
    `select job.enfileirar($1, $2::uuid, $3, $4::jsonb, $5) as enfileirar`,
    [
      pedido.tipo,
      pedido.documentoId,
      pedido.chaveIdempotencia,
      JSON.stringify(pedido.payload ?? {}),
      pedido.prioridade ?? 100,
    ],
  );
  // `null` significa "já existe trabalho igual pendente ou em curso". Não é erro:
  // é a idempotência de fila funcionando, e reenfileirar depois que o anterior
  // concluiu continua permitido — era isso que a unicidade total quebrava.
  return rows[0]?.enfileirar ?? null;
}

export function chaveDe(
  tipo: TipoDeJob,
  alvo: string,
  versaoPipeline: number,
  sufixo?: string | number,
): string {
  return `${tipo}:${alvo}:v${versaoPipeline}${sufixo === undefined ? "" : `:${sufixo}`}`;
}
