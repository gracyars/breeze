/**
 * Semeadura de desenvolvimento: cria a editora e a deixa pronta para entrar.
 *
 * Existe porque F1 tem um ovo-e-galinha real: `service_role` **não tem INSERT em
 * `documentos`** (decisão de F0, V4 da auditoria), então nem o backfill do acervo
 * roda sem uma editora autenticada — e não há editora até alguém criar a
 * primeira. Em produção essa primeira concessão é uma cerimônia manual,
 * registrada; aqui é um script, e ele **só roda contra o stack local**.
 *
 * Uso:
 *   pnpm dev:semeia-editora [email] [--com-totp]
 *
 * Sem `--com-totp`: entre por `/entrar`, pegue o link no Mailpit
 * (http://127.0.0.1:54324) e cadastre o segundo fator em `/seguranca`.
 *
 * Com `--com-totp`: o script enrola o segundo fator e imprime o `otpauth://`
 * para você apontar o app autenticador. Serve para poder rodar `pnpm backfill`,
 * que **exige** `aal2` — sem segundo fator a RLS trata a editora como moradora,
 * por desenho (ADR-0003). O segredo aparece uma vez, no seu terminal, e não é
 * gravado em lugar nenhum: se perder, enrole de novo.
 */
import { randomUUID } from "node:crypto";
import { readFileSync } from "node:fs";

import { Client } from "pg";

function env(chave: string): string {
  if (process.env[chave]) return process.env[chave]!;
  const arquivo = readFileSync(new URL("../../.env.local", import.meta.url), "utf8");
  const linha = arquivo.split("\n").find((l) => l.startsWith(`${chave}=`));
  if (!linha) throw new Error(`${chave} ausente no ambiente e em .env.local`);
  return linha.slice(chave.length + 1).trim();
}

const URL_SUPABASE = env("NEXT_PUBLIC_SUPABASE_URL");
if (!URL_SUPABASE.includes("127.0.0.1") && !URL_SUPABASE.includes("localhost")) {
  console.error(
    "Recusado: este script é de desenvolvimento e só roda contra o Supabase local.\n" +
      "Conceder papel de editora em produção é cerimônia manual e registrada (SPEC §2.1, D4).",
  );
  process.exit(1);
}

const comTotp = process.argv.includes("--com-totp");
const email = (
  process.argv.slice(2).find((a) => !a.startsWith("--")) ?? "editora@breeze.local"
).toLowerCase();

const auth = await fetch(`${URL_SUPABASE}/auth/v1/admin/users`, {
  method: "POST",
  headers: {
    apikey: env("SUPABASE_SERVICE_ROLE_KEY"),
    authorization: `Bearer ${env("SUPABASE_SERVICE_ROLE_KEY")}`,
    "content-type": "application/json",
  },
  body: JSON.stringify({ email, email_confirm: true }),
});
const usuario = (await auth.json()) as { id?: string; msg?: string };
if (!usuario.id) {
  console.error("Auth recusou criar o usuário:", usuario);
  process.exit(1);
}

const cliente = new Client({ connectionString: env("SUPABASE_DB_URL") });
await cliente.connect();

const { rows } = await cliente.query<{ id: string }>(
  `insert into public.pessoas (auth_user_id, nome, email)
   values ($1, $2, $3)
   on conflict (email) do update set auth_user_id = excluded.auth_user_id
   returning id`,
  [usuario.id, "Editora do Breeze", email],
);
const pessoaId = rows[0].id;

// `editor` é único (D4) e o schema impede deixar o sistema sem editor vigente
// (ADR-0022, INV-02). Encerrar o mandato anterior e abrir o novo tem de acontecer
// numa transação só — senão o banco recusa, com razão.
await cliente.query("begin");
await cliente.query(
  // `now()`, não `current_date`: a vigência é intervalo de instantes desde o
  // ADR-0030, e `current_date` gravaria a meia-noite de hoje — antedatando o
  // início do mandato em até 24 h no registro que a trilha vai mostrar.
  `insert into public.papeis (pessoa_id, papel, mandato_inicio, motivo)
   values ($1, 'editor', now(), $2)
   on conflict do nothing`,
  [pessoaId, `semeadura de desenvolvimento ${randomUUID().slice(0, 8)}`],
);
await cliente.query("commit");

await cliente.end();

if (comTotp) {
  const linkResposta = await fetch(`${URL_SUPABASE}/auth/v1/admin/generate_link`, {
    method: "POST",
    headers: {
      apikey: env("SUPABASE_SERVICE_ROLE_KEY"),
      authorization: `Bearer ${env("SUPABASE_SERVICE_ROLE_KEY")}`,
      "content-type": "application/json",
    },
    body: JSON.stringify({ type: "magiclink", email }),
  });
  const { email_otp } = (await linkResposta.json()) as { email_otp: string };

  const sessaoResposta = await fetch(`${URL_SUPABASE}/auth/v1/verify`, {
    method: "POST",
    headers: {
      apikey: env("NEXT_PUBLIC_SUPABASE_ANON_KEY"),
      "content-type": "application/json",
    },
    body: JSON.stringify({ type: "magiclink", email, token: email_otp }),
  });
  const sessao = (await sessaoResposta.json()) as { access_token?: string };

  const fatorResposta = await fetch(`${URL_SUPABASE}/auth/v1/factors`, {
    method: "POST",
    headers: {
      apikey: env("NEXT_PUBLIC_SUPABASE_ANON_KEY"),
      authorization: `Bearer ${sessao.access_token}`,
      "content-type": "application/json",
    },
    body: JSON.stringify({ factor_type: "totp", friendly_name: `breeze-${Date.now()}` }),
  });
  const fator = (await fatorResposta.json()) as {
    totp?: { secret: string; uri: string };
    msg?: string;
  };

  if (!fator.totp) {
    console.error("Não consegui enrolar o segundo fator:", fator);
  } else {
    console.log("\nSegundo fator — aponte seu app autenticador para:");
    console.log(`  ${fator.totp.uri}`);
    console.log(`  (ou digite a chave: ${fator.totp.secret})`);
    console.log(
      "\nDepois verifique o código uma vez em /seguranca; enquanto não verificar,\n" +
        "o fator fica pendente e a editora continua sem aal2.",
    );
  }
}

console.log(`Editora pronta: ${email}`);
console.log(`  pessoa_id : ${pessoaId}`);
console.log(`  auth_user : ${usuario.id}`);
console.log("\nEntre em http://127.0.0.1:3000/entrar e pegue o link em http://127.0.0.1:54324");
