/**
 * Sonda D1 — o GoTrue emite `aal2` só depois da verificação do TOTP?
 *
 * Toda a autorização de papel privilegiado do Breeze depende disso. A RLS
 * reconhece `editor` e `conselho` apenas quando o JWT traz `aal2` (ADR-0003,
 * ADR-0012); sessão de conselheiro em AAL1 é tratada como morador. Só que os 176
 * asserts de pgTAP **simulam** o claim `aal` no token de teste — nenhum deles
 * exercitou o Auth de verdade. Se o GoTrue emitisse `aal2` já no enrolamento,
 * antes da primeira verificação, bastaria enrolar um fator e nunca confirmá-lo
 * para virar editora: a suíte inteira estaria medindo uma garantia mais forte do
 * que o sistema tem. É a dívida D1 de `docs/ops/divida-tecnica.md`, e é o
 * primeiro teste do corte C1 de `docs/f1-plano.md`.
 *
 * Roda contra o stack local:
 *   node --experimental-strip-types scripts/probe/aal2-gotrue.ts
 *
 * Exige `[auth.mfa.totp] enroll_enabled = true` e `verify_enabled = true` em
 * `supabase/config.toml`. Falha de sonda é achado bloqueante de F1, não é bug de
 * script — leia a saída antes de concluir qualquer coisa.
 */
import { createHmac, randomUUID } from "node:crypto";

const URL_AUTH = `${process.env.SUPABASE_URL ?? "http://127.0.0.1:54321"}/auth/v1`;
const CHAVE_ANON =
  process.env.SUPABASE_ANON_KEY ??
  "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0";

let falhas = 0;

function checa(condicao: boolean, descricao: string, detalhe?: unknown): void {
  if (condicao) {
    console.log(`  ok   ${descricao}`);
    return;
  }
  falhas += 1;
  console.log(`  FALHA ${descricao}`);
  if (detalhe !== undefined) {
    console.log(`       ${JSON.stringify(detalhe)}`);
  }
}

async function chamar(
  caminho: string,
  opcoes: { metodo?: string; token?: string; corpo?: unknown } = {},
): Promise<{ status: number; json: Record<string, unknown> }> {
  const resposta = await fetch(`${URL_AUTH}${caminho}`, {
    method: opcoes.metodo ?? "GET",
    headers: {
      apikey: CHAVE_ANON,
      "content-type": "application/json",
      ...(opcoes.token ? { authorization: `Bearer ${opcoes.token}` } : {}),
    },
    ...(opcoes.corpo ? { body: JSON.stringify(opcoes.corpo) } : {}),
  });
  const texto = await resposta.text();
  let json: Record<string, unknown> = {};
  try {
    json = texto ? JSON.parse(texto) : {};
  } catch {
    json = { corpo_bruto: texto };
  }
  return { status: resposta.status, json };
}

/** Lê os claims do access token sem validar assinatura — é diagnóstico, não autenticação. */
function claims(token: string): Record<string, unknown> {
  const [, carga] = token.split(".");
  return JSON.parse(Buffer.from(carga, "base64url").toString("utf8"));
}

const ALFABETO_BASE32 = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";

function base32ParaBytes(segredo: string): Buffer {
  let bits = "";
  for (const caractere of segredo.toUpperCase().replace(/=+$/, "")) {
    const indice = ALFABETO_BASE32.indexOf(caractere);
    if (indice === -1) continue;
    bits += indice.toString(2).padStart(5, "0");
  }
  const bytes: number[] = [];
  for (let i = 0; i + 8 <= bits.length; i += 8) {
    bytes.push(Number.parseInt(bits.slice(i, i + 8), 2));
  }
  return Buffer.from(bytes);
}

/** TOTP RFC 6238 (SHA-1, 30 s, 6 dígitos) — o que qualquer app autenticador gera. */
function codigoTotp(segredo: string, emSegundos = Date.now() / 1000): string {
  const contador = Math.floor(emSegundos / 30);
  const buffer = Buffer.alloc(8);
  buffer.writeBigUInt64BE(BigInt(contador));
  const hmac = createHmac("sha1", base32ParaBytes(segredo)).update(buffer).digest();
  const deslocamento = hmac[hmac.length - 1] & 0x0f;
  const binario =
    ((hmac[deslocamento] & 0x7f) << 24) |
    ((hmac[deslocamento + 1] & 0xff) << 16) |
    ((hmac[deslocamento + 2] & 0xff) << 8) |
    (hmac[deslocamento + 3] & 0xff);
  return String(binario % 1_000_000).padStart(6, "0");
}

async function main(): Promise<void> {
  const email = `sonda-aal-${randomUUID()}@breeze.local`;
  const senha = `sonda-${randomUUID()}`;

  console.log(`Sonda D1 — ${URL_AUTH}\n`);

  console.log("1. Conta nova, sem segundo fator");
  const cadastro = await chamar("/signup", {
    metodo: "POST",
    corpo: { email, password: senha },
  });
  const tokenInicial = cadastro.json.access_token as string | undefined;
  if (!tokenInicial) {
    console.log("  FALHA não obtive sessão no signup", cadastro.json);
    process.exit(1);
  }
  const claimsIniciais = claims(tokenInicial);
  checa(claimsIniciais.aal === "aal1", "sessão sem fator nasce em aal1", claimsIniciais.aal);

  console.log("\n2. Enrolamento do TOTP — o momento que a dívida D1 questiona");
  const enrolamento = await chamar("/factors", {
    metodo: "POST",
    token: tokenInicial,
    corpo: { factor_type: "totp", friendly_name: `sonda-${Date.now()}` },
  });
  if (enrolamento.status !== 200) {
    console.log("  FALHA enrolamento recusado", enrolamento);
    console.log(
      "\n  Se a mensagem fala em MFA desabilitado, ligue [auth.mfa.totp] em supabase/config.toml",
    );
    process.exit(1);
  }
  const fatorId = enrolamento.json.id as string;
  const segredo = (enrolamento.json.totp as { secret: string }).secret;
  checa(Boolean(fatorId && segredo), "enrolamento devolveu fator e segredo");

  const claimsPosEnrolamento = claims(tokenInicial);
  checa(
    claimsPosEnrolamento.aal === "aal1",
    "token existente continua aal1 depois do enrolamento",
    claimsPosEnrolamento.aal,
  );

  // O teste que importa: renovar a sessão depois do enrolamento e antes de
  // qualquer verificação. Se o GoTrue promovesse aqui, enrolar sem nunca
  // confirmar bastaria para virar editora.
  const renovado = await chamar("/token?grant_type=refresh_token", {
    metodo: "POST",
    corpo: { refresh_token: cadastro.json.refresh_token },
  });
  const tokenRenovado = renovado.json.access_token as string;
  const claimsRenovados = claims(tokenRenovado);
  checa(
    claimsRenovados.aal === "aal1",
    "token RENOVADO após enrolamento ainda é aal1 (sem verificar o fator)",
    claimsRenovados,
  );

  const fatores = await chamar("/user", { token: tokenRenovado });
  const listados =
    ((fatores.json.factors as { id: string; status: string }[] | undefined) ?? []);
  const fator = listados.find((f) => f.id === fatorId);
  checa(
    fator?.status === "unverified",
    "fator recém-enrolado fica como não verificado",
    fator?.status,
  );

  console.log("\n3. Código errado não promove");
  const desafio = await chamar(`/factors/${fatorId}/challenge`, {
    metodo: "POST",
    token: tokenRenovado,
  });
  const desafioId = desafio.json.id as string;
  const errado = await chamar(`/factors/${fatorId}/verify`, {
    metodo: "POST",
    token: tokenRenovado,
    corpo: { challenge_id: desafioId, code: "000000" },
  });
  checa(errado.status >= 400, "verificação com código errado é recusada", errado.status);
  checa(
    errado.json.access_token === undefined,
    "recusa não devolve token novo",
    Object.keys(errado.json),
  );

  console.log("\n4. Código certo promove para aal2");
  const desafio2 = await chamar(`/factors/${fatorId}/challenge`, {
    metodo: "POST",
    token: tokenRenovado,
  });
  const certo = await chamar(`/factors/${fatorId}/verify`, {
    metodo: "POST",
    token: tokenRenovado,
    corpo: { challenge_id: desafio2.json.id, code: codigoTotp(segredo) },
  });
  const tokenVerificado = certo.json.access_token as string | undefined;
  checa(Boolean(tokenVerificado), "verificação com código certo devolve token", certo.status);
  if (tokenVerificado) {
    const claimsVerificados = claims(tokenVerificado);
    checa(
      claimsVerificados.aal === "aal2",
      "token pós-verificação é aal2",
      claimsVerificados.aal,
    );
  }

  console.log("\n5. Login novo volta a aal1 — aal2 não é permanente");
  const relogin = await chamar("/token?grant_type=password", {
    metodo: "POST",
    corpo: { email, password: senha },
  });
  const tokenRelogin = relogin.json.access_token as string;
  const claimsRelogin = claims(tokenRelogin);
  checa(
    claimsRelogin.aal === "aal1",
    "sessão nova de usuário COM fator verificado nasce em aal1",
    claimsRelogin.aal,
  );

  // A sonda não deixa rastro: a conta criada aqui some no fim. Assert de auditoria
  // que compara a tabela inteira quebra com qualquer linha esquecida (aconteceu).
  const usuarioId = claims(tokenInicial).sub as string;
  await fetch(`${URL_AUTH}/admin/users/${usuarioId}`, {
    method: "DELETE",
    headers: {
      apikey: process.env.SUPABASE_SERVICE_ROLE_KEY ?? CHAVE_ANON,
      authorization: `Bearer ${process.env.SUPABASE_SERVICE_ROLE_KEY ?? CHAVE_ANON}`,
    },
  });

  console.log(
    falhas === 0
      ? "\nD1 fechada: o GoTrue só emite aal2 depois da verificação do segundo fator."
      : `\n${falhas} verificação(ões) falharam — achado BLOQUEANTE de F1, leia acima.`,
  );
  process.exit(falhas === 0 ? 0 : 1);
}

await main();
