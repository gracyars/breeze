/**
 * Worker de ingestão — o consumidor da `job.fila` (ADR-0025).
 *
 * Roda na máquina da mantenedora, não num servidor. A razão não é falta de
 * infraestrutura: é que quem sobe documento é quem tem a máquina, e um worker
 * remoto precisaria de credencial de escrita permanente num servidor sem
 * ninguém olhando (risco D4).
 *
 *   node --experimental-strip-types scripts/worker/index.ts          # laço
 *   node --experimental-strip-types scripts/worker/index.ts --uma-vez # drena e sai
 *
 * Concorrência 1, de propósito: o estágio caro é OCR, limitado por CPU.
 * Paralelismo aqui só adiciona modo de falha para ganhar segundos.
 */
import { readFileSync } from "node:fs";

import { createClient } from "@supabase/supabase-js";
import { Pool } from "pg";

import {
  chunking,
  documentoDoJob,
  extracaoNativa,
  hashDedupe,
  ocrPagina,
  type Contexto,
} from "@/lib/ingestao/estagios";
import {
  concluiJob,
  falhaJob,
  tomaJob,
  varreLeasesExpirados,
  type Job,
} from "@/lib/ingestao/fila";

function env(chave: string): string {
  if (process.env[chave]) return process.env[chave]!;
  const arquivo = readFileSync(new URL("../../.env.local", import.meta.url), "utf8");
  const linha = arquivo.split("\n").find((l) => l.startsWith(`${chave}=`));
  if (!linha) throw new Error(`${chave} ausente no ambiente e em .env.local`);
  return linha.slice(chave.length + 1).trim();
}

const umaVez = process.argv.includes("--uma-vez");
const INTERVALO_MS = 2_000;

const pool = new Pool({ connectionString: env("SUPABASE_DB_URL"), max: 1 });

// O worker fala com o banco com os privilégios de `service_role`, não de
// superusuário: `set role` faz o próprio Postgres impor o mesmo teto que a
// aplicação tem. Continua sendo bypass de RLS — por isso ele só toca tabela de
// saída de máquina (`documento_paginas`, `chunks`) e nunca cria documento:
// `service_role` não tem INSERT em `documentos`, por decisão de F0.
pool.on("connect", (cliente) => {
  void cliente.query("set role service_role");
});

const supabase = createClient(
  env("NEXT_PUBLIC_SUPABASE_URL"),
  env("SUPABASE_SERVICE_ROLE_KEY"),
  { auth: { autoRefreshToken: false, persistSession: false } },
);

const contexto: Omit<Contexto, "db"> = {
  async baixaObjeto(bucket, caminho) {
    const { data, error } = await supabase.storage.from(bucket).download(caminho);
    if (error || !data) {
      throw new Error(`falha ao baixar ${bucket}/${caminho}: ${error?.message}`);
    }
    return new Uint8Array(await data.arrayBuffer());
  },
};

const ESTAGIOS = {
  hash_dedupe: hashDedupe,
  extracao_nativa: extracaoNativa,
  ocr_pagina: ocrPagina,
  chunking,
} as const;

async function processa(job: Job): Promise<void> {
  const cliente = await pool.connect();
  try {
    const estagio = ESTAGIOS[job.tipo as keyof typeof ESTAGIOS];
    if (!estagio) {
      // Estágios de LLM (`embedding_lote`, `classificacao`) existem na fila e
      // nascem desligados em F1 (ADR-0027). Ficam pendentes até haver chave —
      // não são erro, e por isso não morrem.
      console.log(`  · ${job.tipo} não está ligado nesta fase; devolvido à fila`);
      await cliente.query(
        `update job.fila set status = 'pendente', disponivel_em = now() + interval '1 day' where id = $1`,
        [job.id],
      );
      return;
    }

    const inicio = Date.now();
    await estagio({ ...contexto, db: cliente }, job);
    await concluiJob(cliente, job.id);
    console.log(`  ✓ ${job.tipo} (${Date.now() - inicio}ms)`);
  } catch (erro) {
    let documentoId: string | undefined;
    try {
      documentoId = documentoDoJob(job);
    } catch {
      documentoId = undefined;
    }
    const desfecho = await falhaJob(cliente, job, erro, documentoId);
    const mensagem = erro instanceof Error ? erro.message : String(erro);
    console.error(
      desfecho === "morto"
        ? `  ✗ ${job.tipo} MORREU: ${mensagem}\n    (documento marcado com erro — alguém precisa olhar)`
        : `  ↺ ${job.tipo} falhou, vai tentar de novo: ${mensagem}`,
    );
  } finally {
    cliente.release();
  }
}

async function ciclo(): Promise<number> {
  const cliente = await pool.connect();
  let devolvidos = 0;
  try {
    // Varre lease expirado a cada ciclo: o caso que importa é "o worker morreu e
    // voltou", e sem isto um crash engole o documento em silêncio.
    devolvidos = await varreLeasesExpirados(cliente);
    if (devolvidos > 0) {
      console.log(`  ↩ ${devolvidos} job(s) presos por worker morto voltaram para a fila`);
    }
  } finally {
    cliente.release();
  }

  let processados = 0;
  for (;;) {
    const cliente = await pool.connect();
    let job: Job | null;
    try {
      job = await tomaJob(cliente);
    } finally {
      cliente.release();
    }
    if (!job) break;
    console.log(`→ job ${job.id} ${job.tipo} (tentativa ${job.tentativas})`);
    await processa(job);
    processados += 1;
  }
  return processados;
}

let encerrando = false;
for (const sinal of ["SIGINT", "SIGTERM"] as const) {
  process.on(sinal, () => {
    console.log("\nEncerrando depois do job atual…");
    encerrando = true;
  });
}

if (umaVez) {
  const total = await ciclo();
  console.log(`${total} job(s) processado(s).`);
  await pool.end();
} else {
  console.log("Worker de ingestão no ar. Ctrl+C para parar.");
  while (!encerrando) {
    const total = await ciclo();
    if (total === 0) {
      await new Promise((resolva) => setTimeout(resolva, INTERVALO_MS));
    }
  }
  await pool.end();
}
