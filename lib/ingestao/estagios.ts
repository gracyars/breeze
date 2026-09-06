import { createHash } from "node:crypto";

import type { PoolClient } from "pg";

import { chunkiza, type PaginaParaChunk } from "@/lib/ingestao/chunker";
import { extraiTextoNativo, exigeOcrAutomatico } from "@/lib/ingestao/extracao";
import { chaveDe, enfileira, ErroPermanente, type Job } from "@/lib/ingestao/fila";
import { ocrDePaginas } from "@/lib/ingestao/ocr";

/**
 * Os estágios do pipeline de ingestão (ADR-0025).
 *
 * Duas regras valem para todos, e são o que faz o pipeline ser retomável:
 *
 * 1. **Nenhum efeito externo dentro da transação.** Baixar do Storage e rodar o
 *    OCR acontecem antes de abrir a transação de escrita.
 * 2. **O enfileiramento do próximo estágio commita junto com a escrita deste.**
 *    Não existe "escreveu e não enfileirou": ou os dois, ou nenhum. É o que a
 *    fila no mesmo Postgres dá de graça, e é a razão de ela estar lá.
 *
 * Idempotência mora no dado, não na fila: cada estágio é `update` ou
 * `delete`+`insert` sobre chave natural determinística. Rodar duas vezes
 * converge para o mesmo estado, mesmo que a fila inteira seja perdida e refeita.
 */

export interface Contexto {
  db: PoolClient;
  /** Baixa o objeto do Storage. Efeito externo — sempre fora da transação. */
  baixaObjeto: (bucket: string, caminho: string) => Promise<Uint8Array>;
}

interface DocumentoParaProcessar {
  id: string;
  storage_bucket: string;
  storage_path: string;
  versao_pipeline: number;
  visibilidade: string;
}

export function documentoDoJob(job: Job): string {
  const id = job.payload.documento_id;
  if (typeof id !== "string") {
    throw new ErroPermanente(`job ${job.id} sem documento_id no payload`);
  }
  return id;
}

async function carregaDocumento(
  db: PoolClient,
  documentoId: string,
): Promise<DocumentoParaProcessar> {
  const { rows } = await db.query<DocumentoParaProcessar>(
    `select id, storage_bucket, storage_path, versao_pipeline, visibilidade::text
       from public.documentos where id = $1`,
    [documentoId],
  );
  if (rows.length === 0) {
    // O documento sumiu no meio do caminho: repetir não traz de volta.
    throw new ErroPermanente(`documento ${documentoId} não existe`);
  }
  return rows[0];
}

/**
 * Estágio 1 — hash e deduplicação.
 *
 * O hash é calculado **aqui**, a partir do objeto que realmente chegou, nunca
 * aceito do cliente (ADR-0004: o cliente pode mentir). Por isso `sha256` nasce
 * nulo e é preenchido pelo worker; a violação da unicidade é a detecção de
 * duplicata, não um acidente. O acervo real tem um par byte-idêntico — os dois
 * lembretes da AGE de 04.02.2026 — então este caminho é exercitado no primeiro
 * backfill, não numa hipótese.
 */
export async function hashDedupe(ctx: Contexto, job: Job): Promise<void> {
  const documentoId = documentoDoJob(job);
  const documento = await carregaDocumento(ctx.db, documentoId);

  const bytes = await ctx.baixaObjeto(documento.storage_bucket, documento.storage_path);
  // O tamanho é lido ANTES de o PDF ser aberto: o pdf.js assume a posse do
  // buffer que recebe e o desacopla, e a partir daí `byteLength` é 0. Isso
  // chegou a gravar `bytes = 0` e ser barrado pelo check do schema — o banco
  // pegou o que o código deixou passar.
  const tamanho = bytes.byteLength;
  const sha256 = createHash("sha256").update(bytes).digest();
  const paginas = await contaPaginas(bytes);

  await ctx.db.query("begin");
  try {
    const duplicata = await ctx.db.query<{ id: string }>(
      `select id from public.documentos where sha256 = $1 and id <> $2`,
      [sha256, documentoId],
    );

    if (duplicata.rowCount) {
      // Duplicata não é erro de máquina: é informação para uma pessoa decidir.
      // O documento fica em `erro` com o motivo legível, e a UI oferece
      // descartar ou seguir assim mesmo.
      await ctx.db.query(
        `update public.documentos
            set status = 'erro',
                erro_detalhe = $2,
                bytes = $3,
                paginas = $4
          where id = $1`,
        [
          documentoId,
          `Arquivo idêntico a um documento já no acervo (${duplicata.rows[0].id}).`,
          tamanho,
          paginas,
        ],
      );
      await ctx.db.query("commit");
      return;
    }

    await ctx.db.query(
      `update public.documentos
          set sha256 = $2, bytes = $3, paginas = $4, status = 'processando'
        where id = $1`,
      [documentoId, sha256, tamanho, paginas],
    );

    await enfileira(ctx.db, {
      tipo: "extracao_nativa",
      documentoId,
      chaveIdempotencia: chaveDe(
        "extracao_nativa",
        sha256.toString("hex"),
        documento.versao_pipeline,
      ),
    });

    await ctx.db.query("commit");
  } catch (erro) {
    await ctx.db.query("rollback");
    throw erro;
  }
}

/**
 * Estágio 2 — extração nativa de todas as páginas.
 *
 * `texto_nativo` guarda o que o PDF trazia e **nunca** é sobrescrito depois; o
 * OCR só mexe em `texto`. Reverter um OCR ruim é trocar `texto` de volta, sem
 * reprocessar nada (ADR-0024).
 *
 * Só página **vazia** enfileira OCR automático. A faixa duvidosa (texto pouco ou
 * com cara de ruído) vira proposta na tela de conferência, porque com OCR local
 * o custo do falso positivo deixou de ser dinheiro e passou a ser sobrescrever
 * texto nativo correto — que é pior.
 */
export async function extracaoNativa(ctx: Contexto, job: Job): Promise<void> {
  const documentoId = documentoDoJob(job);
  const documento = await carregaDocumento(ctx.db, documentoId);
  const bytes = await ctx.baixaObjeto(documento.storage_bucket, documento.storage_path);

  const { paginas } = await extraiTextoNativo(bytes);

  await ctx.db.query("begin");
  try {
    for (const pagina of paginas) {
      await ctx.db.query(
        `insert into public.documento_paginas
           (documento_id, pagina, texto, texto_nativo, fonte_texto, versao_pipeline)
         values ($1, $2, $3, $4, $5, $6)
         on conflict (documento_id, pagina) do update
            set texto = excluded.texto,
                texto_nativo = excluded.texto_nativo,
                fonte_texto = excluded.fonte_texto,
                versao_pipeline = excluded.versao_pipeline`,
        [
          documentoId,
          pagina.pagina,
          pagina.texto,
          pagina.textoNativo,
          pagina.fonteTexto,
          documento.versao_pipeline,
        ],
      );

      if (exigeOcrAutomatico(pagina)) {
        await enfileira(ctx.db, {
          tipo: "ocr_pagina",
          documentoId,
          payload: { pagina: pagina.pagina },
          chaveIdempotencia: chaveDe(
            "ocr_pagina",
            documentoId,
            documento.versao_pipeline,
            pagina.pagina,
          ),
          // OCR antes de chunking na fila: o chunk de página vazia não serve
          // para nada, e reprocessar depois custa mais que esperar agora.
          prioridade: 50,
        });
      }
    }

    await enfileira(ctx.db, {
      tipo: "chunking",
      documentoId,
      chaveIdempotencia: chaveDe("chunking", documentoId, documento.versao_pipeline),
      prioridade: 200,
    });

    await ctx.db.query("commit");
  } catch (erro) {
    await ctx.db.query("rollback");
    throw erro;
  }
}

/** Estágio 3 — OCR de UMA página, com o motor local (ADR-0024). */
export async function ocrPagina(ctx: Contexto, job: Job): Promise<void> {
  const documentoId = documentoDoJob(job);
  const pagina = Number(job.payload.pagina);
  if (!Number.isInteger(pagina) || pagina < 1) {
    throw new ErroPermanente(`job ${job.id} com página inválida`);
  }

  const documento = await carregaDocumento(ctx.db, documentoId);
  const bytes = await ctx.baixaObjeto(documento.storage_bucket, documento.storage_path);

  const [resultado] = await ocrDePaginas(bytes, [pagina]);
  if (!resultado) {
    throw new ErroPermanente(`OCR não devolveu a página ${pagina} de ${documentoId}`);
  }

  await ctx.db.query("begin");
  try {
    await ctx.db.query(
      `update public.documento_paginas
          set texto = $3, fonte_texto = 'ocr', confianca_ocr = $4
        where documento_id = $1 and pagina = $2`,
      [documentoId, pagina, resultado.texto, resultado.confianca],
    );
    await ctx.db.query(
      `update public.documentos set ocr_aplicado = true where id = $1`,
      [documentoId],
    );
    // O chunking do documento inteiro é reenfileirado: a página que estava vazia
    // agora tem texto, e o chunk que a ignorava está errado por omissão.
    await enfileira(ctx.db, {
      tipo: "chunking",
      documentoId,
      chaveIdempotencia: chaveDe("chunking", documentoId, documento.versao_pipeline),
      prioridade: 200,
    });
    await ctx.db.query("commit");
  } catch (erro) {
    await ctx.db.query("rollback");
    throw erro;
  }
}

/**
 * Estágio 4 — chunking.
 *
 * `delete` + `insert` no mesmo commit, com escopo
 * `(documento_id, versao_pipeline)`: a unicidade já impede duplicata, e o
 * `delete` garante que um chunking com menos chunks que o anterior não deixe
 * cauda órfã apontando para texto que não existe mais.
 */
export async function chunking(ctx: Contexto, job: Job): Promise<void> {
  const documentoId = documentoDoJob(job);
  const documento = await carregaDocumento(ctx.db, documentoId);

  const { rows } = await ctx.db.query<{
    pagina: number;
    texto: string | null;
    visibilidade: string | null;
  }>(
    `select pagina, texto, visibilidade::text
       from public.documento_paginas
      where documento_id = $1
      order by pagina`,
    [documentoId],
  );

  const paginas: PaginaParaChunk[] = rows.map((linha) => ({
    pagina: linha.pagina,
    texto: linha.texto ?? "",
    visibilidade: linha.visibilidade,
  }));

  const chunks = chunkiza(paginas, documento.visibilidade);

  await ctx.db.query("begin");
  try {
    await ctx.db.query(
      `delete from public.chunks where documento_id = $1 and versao_pipeline = $2`,
      [documentoId, documento.versao_pipeline],
    );

    for (const chunk of chunks) {
      await ctx.db.query(
        `insert into public.chunks
           (documento_id, pagina_ini, pagina_fim, ordem, texto, tokens, secao, versao_pipeline)
         values ($1, $2, $3, $4, $5, $6, $7, $8)`,
        [
          documentoId,
          chunk.paginaIni,
          chunk.paginaFim,
          chunk.ordem,
          chunk.texto,
          chunk.tokens,
          chunk.secao,
          documento.versao_pipeline,
        ],
      );
    }

    // `em_revisao`, não `publicado`: classificação e visibilidade passam por
    // conferência humana antes de qualquer coisa aparecer (SPEC §3.5).
    //
    // **`and status <> 'publicado'` não é detalhe.** Sem essa condição, todo
    // reprocessamento de um documento já publicado — reclassificar uma página,
    // corrigir o chunker, forçar OCR — rebaixaria o status e o documento sumiria
    // da vista do morador enquanto a fila não fosse drenada. É exatamente o
    // estrago que o ADR-0026 §3 veta ao separar `indexado_em` de `status`,
    // entrando por outra porta: a do worker. Documento publicado que reindexa
    // continua publicado; quem sinaliza "fora da busca" é `indexado_em`.
    await ctx.db.query(
      `update public.documentos
          set status = 'em_revisao', erro_detalhe = null
        where id = $1 and status <> 'publicado'`,
      [documentoId],
    );
    // O erro é limpo mesmo no documento publicado: reprocessou e deu certo,
    // então a mensagem antiga viraria mentira na tela.
    await ctx.db.query(
      `update public.documentos set erro_detalhe = null where id = $1 and status = 'publicado'`,
      [documentoId],
    );

    await ctx.db.query("commit");
  } catch (erro) {
    await ctx.db.query("rollback");
    throw erro;
  }
}

async function contaPaginas(bytes: Uint8Array): Promise<number> {
  const { getDocumentProxy } = await import("unpdf");
  try {
    const pdf = await getDocumentProxy(bytes);
    return pdf.numPages;
  } catch (erro) {
    // PDF com senha ou corrompido: repetir não conserta. Vai direto para morto,
    // com mensagem que uma pessoa entende.
    throw new ErroPermanente(
      `não consegui abrir o PDF (com senha ou corrompido): ${
        erro instanceof Error ? erro.message : String(erro)
      }`,
    );
  }
}
