/**
 * Backfill: sobe documento do acervo real e entrega ao pipeline.
 *
 *   pnpm backfill "Documentos do Condomínio/RI - Regulamento Interno.pdf"
 *   pnpm backfill "Documentos do Condomínio" --todos
 *
 * O tipo, o título, a data e a competência saem do **nome do arquivo**, por regra
 * determinística (`lib/acervo/classificacao.ts`, ADR-0029 §3 item 5) — são 43
 * documentos e uma pessoa só; digitar três campos por documento mata a
 * conferência antes do décimo. `--tipo` força um tipo para todo o lote quando a
 * regra não serve.
 *
 * **Por que este script autentica como a editora, e não usa `service_role`:**
 * `service_role` não tem `INSERT` em `documentos` — é decisão de F0 (V4 da
 * auditoria), não limitação. Quem publica no acervo é uma pessoa com papel, e o
 * banco é quem impõe isso. Consequência prática: como `editor` só é reconhecido
 * com `aal2` (ADR-0003), **o script pede o código do segundo fator**. É atrito
 * de propósito: a curadoria dos 43 documentos exige uma pessoa presente de
 * qualquer jeito (SPEC §3.5), e uma máquina que publicasse sozinha no acervo
 * seria exatamente o que o desenho evita.
 *
 * O que ele NÃO faz: publicar. Todo documento entra como `pendente`, vira
 * `em_revisao` quando o pipeline termina, e só a conferência humana publica.
 */
import { createInterface } from "node:readline/promises";
import { readFile, readdir, stat } from "node:fs/promises";
import { readFileSync } from "node:fs";
import { basename, join } from "node:path";
import { randomUUID } from "node:crypto";

import { Client } from "pg";

import { classifica } from "@/lib/acervo/classificacao";

function env(chave: string): string {
  if (process.env[chave]) return process.env[chave]!;
  const arquivo = readFileSync(new URL("../../.env.local", import.meta.url), "utf8");
  const linha = arquivo.split("\n").find((l) => l.startsWith(`${chave}=`));
  if (!linha) throw new Error(`${chave} ausente no ambiente e em .env.local`);
  return linha.slice(chave.length + 1).trim();
}

const URL_SUPABASE = env("NEXT_PUBLIC_SUPABASE_URL");
const CHAVE_ANON = env("NEXT_PUBLIC_SUPABASE_ANON_KEY");
const CHAVE_SERVICO = env("SUPABASE_SERVICE_ROLE_KEY");

interface Argumentos {
  alvo: string;
  /** Força o tipo para todo o lote; vazio = deixa a regra decidir por arquivo. */
  tipo: string;
  todos: boolean;
  email: string;
}

function argumentos(): Argumentos {
  const args = process.argv.slice(2);
  const alvo = args.find((a) => !a.startsWith("--"));
  const valor = (nome: string, padrao: string) => {
    const i = args.indexOf(`--${nome}`);
    return i >= 0 && args[i + 1] ? args[i + 1] : padrao;
  };
  if (!alvo) {
    console.error(
      'uso: pnpm backfill "<arquivo ou pasta>" [--todos] [--tipo <codigo>] [--email <editora>]',
    );
    process.exit(2);
  }
  return {
    alvo,
    tipo: valor("tipo", ""),
    todos: args.includes("--todos"),
    email: valor("email", "editora@breeze.local"),
  };
}

/** Sessão da editora em `aal2` — magic link administrativo + o código do app autenticador. */
async function sessaoDaEditora(email: string): Promise<string> {
  const link = await fetch(`${URL_SUPABASE}/auth/v1/admin/generate_link`, {
    method: "POST",
    headers: {
      apikey: CHAVE_SERVICO,
      authorization: `Bearer ${CHAVE_SERVICO}`,
      "content-type": "application/json",
    },
    body: JSON.stringify({ type: "magiclink", email }),
  });
  const dados = (await link.json()) as { email_otp?: string; msg?: string };
  if (!dados.email_otp) {
    throw new Error(`não consegui gerar acesso para ${email}: ${JSON.stringify(dados)}`);
  }

  // `POST /verify` quer o código do e-mail mais o e-mail; o `hashed_token` é do
  // link clicável (`GET`). Trocar os dois falha com uma mensagem que não explica.
  const verificacao = await fetch(`${URL_SUPABASE}/auth/v1/verify`, {
    method: "POST",
    headers: { apikey: CHAVE_ANON, "content-type": "application/json" },
    body: JSON.stringify({ type: "magiclink", email, token: dados.email_otp }),
  });
  const sessao = (await verificacao.json()) as { access_token?: string };
  if (!sessao.access_token) throw new Error("verificação do link não devolveu sessão");

  const usuario = (await (
    await fetch(`${URL_SUPABASE}/auth/v1/user`, {
      headers: { apikey: CHAVE_ANON, authorization: `Bearer ${sessao.access_token}` },
    })
  ).json()) as { factors?: { id: string; status: string; factor_type: string }[] };

  const fator = usuario.factors?.find(
    (f) => f.status === "verified" && f.factor_type === "totp",
  );
  if (!fator) {
    throw new Error(
      `${email} não tem segundo fator verificado. Cadastre em /seguranca antes — ` +
        "sem aal2 a RLS trata a editora como moradora, e o insert será recusado.",
    );
  }

  const desafio = (await (
    await fetch(`${URL_SUPABASE}/auth/v1/factors/${fator.id}/challenge`, {
      method: "POST",
      headers: { apikey: CHAVE_ANON, authorization: `Bearer ${sessao.access_token}` },
    })
  ).json()) as { id: string };

  const console_ = createInterface({ input: process.stdin, output: process.stdout });
  const codigo = (await console_.question(`Código do autenticador de ${email}: `)).trim();
  console_.close();

  const promovido = (await (
    await fetch(`${URL_SUPABASE}/auth/v1/factors/${fator.id}/verify`, {
      method: "POST",
      headers: {
        apikey: CHAVE_ANON,
        authorization: `Bearer ${sessao.access_token}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({ challenge_id: desafio.id, code: codigo }),
    })
  ).json()) as { access_token?: string; msg?: string };

  if (!promovido.access_token) {
    throw new Error(`segundo fator recusado: ${promovido.msg ?? "código inválido"}`);
  }
  return promovido.access_token;
}

/** Percorre a pasta inteira, subpastas incluídas — o acervo real é assim. */
async function arquivosDe(alvo: string, todos: boolean): Promise<string[]> {
  const info = await stat(alvo);
  if (info.isFile()) return [alvo];
  if (!todos) {
    throw new Error(`${alvo} é uma pasta; use --todos para subir tudo que há nela`);
  }

  const encontrados: string[] = [];
  const entradas = await readdir(alvo, { withFileTypes: true });
  for (const entrada of entradas) {
    const caminho = join(alvo, entrada.name);
    if (entrada.isDirectory()) {
      encontrados.push(...(await arquivosDe(caminho, true)));
    } else if (entrada.name.toLowerCase().endsWith(".pdf")) {
      encontrados.push(caminho);
    }
  }
  return encontrados.sort();
}

async function main(): Promise<void> {
  const { alvo, tipo: tipoForcado, todos, email } = argumentos();
  const arquivos = await arquivosDe(alvo, todos);
  console.log(
    `${arquivos.length} arquivo(s) para subir` +
      (tipoForcado ? ` como tipo "${tipoForcado}".\n` : ", com tipo vindo do nome.\n"),
  );

  const token = await sessaoDaEditora(email);
  const db = new Client({ connectionString: env("SUPABASE_DB_URL") });
  await db.connect();
  await db.query("set role service_role");

  let enviados = 0;
  for (const caminho of arquivos) {
    const nome = basename(caminho);
    const classificacao = classifica(caminho);
    const conteudo = await readFile(caminho);
    // O nome do objeto não carrega informação (ADR-0004 item 5): o título vive na
    // linha, não no caminho. Assim o Storage não vira índice legível de quem
    // conseguir listar o bucket.
    const storagePath = `${randomUUID()}.pdf`;
    // Id gerado aqui: quem sobe o arquivo já precisa dele, e assim o insert não
    // depende de `returning` (que chegou a ser impossível nesta tabela até a
    // migração `20260906100500` tornar o predicado da policy local à linha).
    const documentoId = randomUUID();

    const upload = await fetch(
      `${URL_SUPABASE}/storage/v1/object/documentos/${storagePath}`,
      {
        method: "POST",
        headers: {
          apikey: CHAVE_SERVICO,
          authorization: `Bearer ${CHAVE_SERVICO}`,
          "content-type": "application/pdf",
        },
        body: new Uint8Array(conteudo),
      },
    );
    if (!upload.ok) {
      console.error(`  ✗ ${nome}: upload recusado (${upload.status})`);
      continue;
    }

    // O insert vai com o JWT da editora, nunca com service_role: é a RLS que
    // decide se esta pessoa pode publicar no acervo.
    const criacao = await fetch(`${URL_SUPABASE}/rest/v1/documentos`, {
      method: "POST",
      headers: {
        apikey: CHAVE_ANON,
        authorization: `Bearer ${token}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({
        id: documentoId,
        tipo: tipoForcado || classificacao.tipo,
        titulo: classificacao.titulo.slice(0, 200),
        data_documento: classificacao.dataDocumento,
        competencia: classificacao.competencia,
        storage_bucket: "documentos",
        storage_path: storagePath,
        status: "pendente",
        // Só manda visibilidade quando a regra tem motivo; sem isso, o padrão do
        // tipo prevalece — e o padrão é sempre o mais fechado dos dois.
        ...(classificacao.visibilidade
          ? { visibilidade: classificacao.visibilidade }
          : {}),
      }),
    });

    if (!criacao.ok) {
      console.error(`  ✗ ${nome}: ${criacao.status} ${await criacao.text()}`);
      continue;
    }
    await db.query(`select job.enfileirar($1, $2::uuid, $3, $4::jsonb, $5)`, [
      "hash_dedupe",
      documentoId,
      `hash_dedupe:${documentoId}:v1`,
      "{}",
      100,
    ]);

    enviados += 1;
    console.log(
      `  ✓ ${nome}\n      ${tipoForcado || classificacao.tipo}` +
        `${classificacao.dataDocumento ? ` · ${classificacao.dataDocumento}` : ""}` +
        `${classificacao.visibilidade ? ` · ${classificacao.visibilidade}` : ""}` +
        ` — ${classificacao.motivo}`,
    );
  }

  await db.end();
  console.log(
    `\n${enviados}/${arquivos.length} na fila. Rode o worker: pnpm worker:uma-vez`,
  );
}

await main();
