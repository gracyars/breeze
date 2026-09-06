import { execFile } from "node:child_process";
import { createHmac, randomUUID } from "node:crypto";
import { readFileSync } from "node:fs";
import { promisify } from "node:util";

import { expect, test } from "@playwright/test";

import { codigoTotp } from "./totp";

/**
 * Corte C1 — o fluxo de entrada, contra o Supabase de verdade.
 *
 * Exige `supabase start`. Não roda no CI ainda (`pnpm test:e2e`, projeto `e2e`)
 * — wire-up é do `devops`.
 *
 * O caso que mais importa aqui não é o caminho feliz: é a **indistinguibilidade**
 * da resposta. CPF que existe, CPF que não existe e e-mail de ninguém têm de
 * produzir exatamente a mesma tela, senão a página de login vira consulta pública
 * de "esta pessoa mora no Breeze?" (ADR-0003, regra 2).
 */

const executar = promisify(execFile);
/**
 * Marca desta execução. Os testes rodam em paralelo, cada worker com sua própria
 * cópia deste módulo: sem a marca, a limpeza de um worker apagaria a moradora que
 * outro ainda está usando — que foi exatamente o que aconteceu na primeira versão.
 */
const EXECUCAO = randomUUID().slice(0, 8);
const URL_SUPABASE = "http://127.0.0.1:54321";
const URL_MAILPIT = "http://127.0.0.1:54324";
const CHAVE_SERVICO = leEnvLocal("SUPABASE_SERVICE_ROLE_KEY");
const PEPPER = leEnvLocal("CPF_HASH_PEPPER");

/** Lê do `.env.local` — o mesmo arquivo que o `next dev` carrega. */
function leEnvLocal(chave: string): string {
  const conteudo = readFileSync(new URL("../../.env.local", import.meta.url), "utf8");
  const linha = conteudo.split("\n").find((l) => l.startsWith(`${chave}=`));
  if (!linha) throw new Error(`${chave} ausente em .env.local`);
  return linha.slice(chave.length + 1).trim();
}

async function sql(comando: string): Promise<string> {
  const { stdout } = await executar("docker", [
    "exec",
    "supabase_db_breeze",
    "psql",
    "-U",
    "postgres",
    "-d",
    "postgres",
    "-tAc",
    comando,
  ]);
  return stdout.trim();
}

/**
 * CPF sintético válido, sorteado a cada execução.
 *
 * Fixar CPF no teste esbarraria em `pessoas.cpf_hash unique` na segunda rodada —
 * e "limpar a tabela antes" seria pior: `pessoas` não aceita DELETE por desenho
 * (anonimização, não exclusão), então o teste estaria pedindo superusuário para
 * desfazer uma regra do produto.
 */
function geraCpfValido(): string {
  const digitos = Array.from({ length: 9 }, () => Math.floor(Math.random() * 10));
  for (const tamanho of [9, 10]) {
    let soma = 0;
    for (let i = 0; i < tamanho; i += 1) soma += digitos[i] * (tamanho + 1 - i);
    const resto = (soma * 10) % 11;
    digitos.push(resto === 10 ? 0 : resto);
  }
  const cpf = digitos.join("");
  // Sequência repetida passa na conta e é recusada pelo produto: sorteia de novo.
  return /^(\d)\1{10}$/.test(cpf) ? geraCpfValido() : cpf;
}

/** Cria conta no Auth + linha em `pessoas`, amarradas — como a editora faria. */
async function criaMoradora(cpf: string): Promise<{ email: string }> {
  const email = `moradora-${EXECUCAO}-${randomUUID()}@breeze.local`;

  const resposta = await fetch(`${URL_SUPABASE}/auth/v1/admin/users`, {
    method: "POST",
    headers: {
      apikey: CHAVE_SERVICO,
      authorization: `Bearer ${CHAVE_SERVICO}`,
      "content-type": "application/json",
    },
    body: JSON.stringify({ email, email_confirm: true }),
  });
  const usuario = (await resposta.json()) as { id: string };

  const hash = createHmac("sha256", PEPPER).update(cpf, "utf8").digest("hex");
  // `cpf_enc` aqui é preenchimento: a cifra AES-GCM real acontece no cadastro
  // feito pela editora (ADR-0014), que é código de outro corte. O check do
  // schema exige o par preenchido, e é isso que este valor satisfaz.
  await sql(
    `insert into public.pessoas (auth_user_id, nome, email, cpf_hash, cpf_enc, cpf_ultimos_digitos)
     values ('${usuario.id}', 'Moradora de Teste', '${email}', '\\x${hash}', '\\xdeadbeef', '${cpf.slice(6, 9)}')`,
  );

  return { email };
}

async function linkDoUltimoEmail(destinatario: string): Promise<string | null> {
  for (let tentativa = 0; tentativa < 20; tentativa += 1) {
    const lista = (await (
      await fetch(`${URL_MAILPIT}/api/v1/messages`)
    ).json()) as { messages: { ID: string; To: { Address: string }[] }[] };

    const mensagem = lista.messages.find((m) =>
      m.To.some((t) => t.Address === destinatario),
    );
    if (mensagem) {
      const corpo = await (
        await fetch(`${URL_MAILPIT}/api/v1/message/${mensagem.ID}`)
      ).json();
      const texto = `${corpo.HTML ?? ""}${corpo.Text ?? ""}`;
      const link = texto.match(/https?:\/\/[^"'\s<>]+/g)?.find((u) => u.includes("verify"));
      return link ? link.replace(/&amp;/g, "&") : null;
    }
    await new Promise((resolva) => setTimeout(resolva, 250));
  }
  return null;
}

const MESMA_RESPOSTA = /Se houver cadastro com esse CPF ou e-mail/;

/**
 * Limpeza obrigatória: este teste escreve num banco compartilhado.
 *
 * Não é preciosismo. A suíte pgTAP de RLS tem asserts que comparam **a tabela
 * inteira** (ex.: "conselho vê CPF mascarado" lista todos os CPFs mascarados),
 * então cada moradora de teste esquecida em `pessoas` quebra a auditoria de
 * segurança na próxima execução local — foi assim que este bloco nasceu.
 *
 * O `delete` aqui roda como superusuário do container, fora do produto. Dentro
 * do produto ninguém apaga pessoa: o caminho é anonimização (`anonimizada_em`),
 * e nem `service_role` tem DELETE nessa tabela. Fixture de teste não é exceção
 * a essa regra — é outro plano.
 */
test.afterAll(async () => {
  await sql(
    `delete from public.pessoas where email like 'moradora-${EXECUCAO}-%@breeze.local';
     delete from auth.users where email like 'moradora-${EXECUCAO}-%@breeze.local';`,
  );
});

test.describe("entrada", () => {
  test("CPF de quem não mora aqui responde igual a CPF de quem mora", async ({
    page,
  }) => {
    const cpfDaMoradora = geraCpfValido();
    const { email } = await criaMoradora(cpfDaMoradora);

    await page.goto("/entrar");
    await page.getByLabel(/CPF ou e-mail/i).fill(cpfDaMoradora);
    await page.getByRole("button", { name: /Receber link/i }).click();
    const respostaExistente = await page
      .getByRole("status")
      .first()
      .textContent();

    await page.goto("/entrar");
    // CPF sintético válido, de ninguém.
    await page.getByLabel(/CPF ou e-mail/i).fill(geraCpfValido());
    await page.getByRole("button", { name: /Receber link/i }).click();
    const respostaInexistente = await page
      .getByRole("status")
      .first()
      .textContent();

    expect(respostaExistente).toMatch(MESMA_RESPOSTA);
    expect(respostaInexistente).toBe(respostaExistente);

    // E o que separa os dois casos não aparece na tela — aparece na caixa de
    // entrada de quem realmente tem cadastro.
    expect(await linkDoUltimoEmail(email)).not.toBeNull();
  });

  test("o link do e-mail dá sessão, e a sessão nasce sem segundo fator", async ({
    page,
  }) => {
    const { email } = await criaMoradora(geraCpfValido());

    await page.goto("/entrar");
    await page.getByLabel(/CPF ou e-mail/i).fill(email);
    await page.getByRole("button", { name: /Receber link/i }).click();
    await expect(page.getByRole("status").first()).toContainText(MESMA_RESPOSTA);

    const link = await linkDoUltimoEmail(email);
    expect(link).not.toBeNull();
    await page.goto(link!);

    await page.goto("/seguranca");
    await expect(page.getByText(email)).toBeVisible();
    // `aal2` é propriedade da sessão, não da conta (sonda D1): entrar por magic
    // link nunca basta para papel privilegiado.
    await expect(page.getByText(/só o primeiro fator/i)).toBeVisible();
  });

  test("cadastrar e verificar o segundo fator promove a sessão para aal2", async ({
    page,
  }) => {
    const { email } = await criaMoradora(geraCpfValido());

    await page.goto("/entrar");
    await page.getByLabel(/CPF ou e-mail/i).fill(email);
    await page.getByRole("button", { name: /Receber link/i }).click();
    const link = await linkDoUltimoEmail(email);
    await page.goto(link!);

    await page.goto("/seguranca");
    await page.getByRole("button", { name: /Cadastrar segundo fator/i }).click();

    // O segredo aparece na tela para quem não consegue ler o QR — é ele que o
    // app autenticador guardaria. Aqui o teste faz o papel do app.
    const segredo = (await page.locator("p.font-mono").textContent())!.trim();
    await page.getByLabel(/Código de 6 dígitos/i).fill(codigoTotp(segredo));
    await page.getByRole("button", { name: /^Verificar$/ }).click();

    await expect(page.getByText(/Segundo fator verificado nesta sessão/i)).toBeVisible();
  });

  test("rota privada sem sessão volta para o login", async ({ page }) => {
    await page.context().clearCookies();
    await page.goto("/seguranca");
    await expect(page).toHaveURL(/\/entrar/);
  });
});
