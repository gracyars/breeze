import { randomUUID } from "node:crypto";

import { expect, test } from "@playwright/test";

import {
  buscaComo,
  criaDocumento,
  drenaFila,
  editoraComSegundoFator,
  enviaParaStorage,
  linkDoUltimoEmail,
  REGIMENTO,
  sql,
} from "./apoio";
import { codigoTotp } from "./totp";

/**
 * Corte C5 — o ciclo inteiro, pelo navegador: subir, conferir, publicar, achar.
 *
 * É o teste de aceitação de F1. Tudo o mais que existe só vale se esta sequência
 * funcionar para uma pessoa sozinha, sem SQL: o pipeline lê o documento, ele
 * espera na fila de conferência, a editora publica com o segundo fator, e só
 * então o morador — e o anônimo — passam a encontrá-lo.
 */

const EXECUCAO = randomUUID().slice(0, 8);

test.describe("curadoria", () => {
  test.describe.configure({ mode: "serial", timeout: 240_000 });

  test("subir, conferir, publicar — e só então o anônimo acha", async ({ page }) => {
    const editora = await editoraComSegundoFator(`curadoria-${EXECUCAO}`);
    const id = randomUUID();
    const titulo = `Regimento para conferência ${EXECUCAO}`;
    const storagePath = `cur-${EXECUCAO}-${id}.pdf`;

    // 1. O documento entra pelo caminho normal e o worker o lê.
    await enviaParaStorage(REGIMENTO, storagePath);
    const criacao = await criaDocumento(editora.aal2, {
      id,
      tipo: "regimento",
      titulo,
      storage_bucket: "documentos",
      storage_path: storagePath,
      status: "pendente",
    });
    expect(criacao.ok).toBe(true);
    await sql(
      `select job.enfileirar('hash_dedupe','${id}'::uuid,'hash_dedupe:${id}:v1','{}'::jsonb,100)`,
    );
    await drenaFila();

    // 2. Antes de publicar, o anônimo não acha — o pipeline não publica nada.
    const antes = await buscaComo(null, "animais domésticos");
    expect(antes.some((r) => r.titulo === titulo)).toBe(false);

    // 3. A editora entra pelo e-mail, como qualquer pessoa.
    await page.goto("/entrar");
    await page.getByLabel(/CPF ou e-mail/i).fill(editora.email);
    await page.getByRole("button", { name: /Receber link/i }).click();
    const link = await linkDoUltimoEmail(editora.email);
    expect(link).not.toBeNull();
    await page.goto(link!);

    // 4. Sem o segundo fator, a conferência avisa — e o banco recusaria de todo
    //    jeito, porque a policy de UPDATE exige `aal2`.
    await page.goto("/curadoria");
    await expect(page.getByText(/Publicar exige o segundo fator/i)).toBeVisible();

    await page.goto("/seguranca");
    await page.getByLabel(/Código de 6 dígitos/i).fill(codigoTotp(editora.segredoTotp));
    await page.getByRole("button", { name: /^Verificar$/ }).click();
    await expect(page.getByText(/Segundo fator verificado/i)).toBeVisible();

    // 5. A fila mostra o documento e o começo do texto lido, para conferir.
    await page.goto("/curadoria");
    await expect(page.getByText(titulo)).toBeVisible();
    await expect(page.getByText(/REGULAMENTO INTERNO/i)).toBeVisible();

    await page.getByLabel(/Quem pode ver/i).selectOption("publico");
    await page.getByRole("button", { name: /^Publicar$/ }).click();

    // 6. Publicado — e agora o anônimo acha.
    await expect
      .poll(async () => await sql(`select status from public.documentos where id = '${id}'`))
      .toBe("publicado");

    const depois = await buscaComo(null, "animais domésticos");
    expect(depois.some((r) => r.titulo === titulo)).toBe(true);
  });

  test.afterAll(async () => {
    await sql(
      `delete from public.chunks where documento_id in
         (select id from public.documentos where titulo like '%${EXECUCAO}%');
       delete from public.documento_paginas where documento_id in
         (select id from public.documentos where titulo like '%${EXECUCAO}%');
       delete from job.fila where payload->>'documento_id' in
         (select id::text from public.documentos where titulo like '%${EXECUCAO}%');
       delete from public.documentos where titulo like '%${EXECUCAO}%';
       delete from public.papeis where pessoa_id in
         (select id from public.pessoas where email like 'curadoria-${EXECUCAO}-%');
       delete from public.pessoas where email like 'curadoria-${EXECUCAO}-%';
       delete from auth.users where email like 'curadoria-${EXECUCAO}-%';`,
    );
  });
});
