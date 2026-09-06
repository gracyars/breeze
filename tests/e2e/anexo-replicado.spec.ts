import { randomUUID } from "node:crypto";

import { expect, test } from "@playwright/test";

import {
  criaDocumento,
  linkDoUltimoEmail,
  drenaFila,
  editoraComSegundoFator,
  enviaParaStorage,
  REGIMENTO,
  sql,
} from "./apoio";

/**
 * Corte C8 — o anexo replicado, contra os dois documentos reais.
 *
 * A ata da AGE de 04.02.2026 embute o Regimento Interno inteiro. É o caso que o
 * ADR-0028 descreve e que apareceu sozinho assim que o acervo foi carregado:
 * buscar "animais domésticos" devolvia a mesma regra duas vezes, e o morador não
 * tinha como saber que eram a mesma coisa nem qual citar.
 *
 * A busca aqui é feita **logada**, e não por acaso: ata não pode ser pública (só
 * convenção e regimento podem, e o schema recusa o contrário), então para o
 * anônimo a ata não existe e não há duplicata nenhuma. Quem vê as duas cópias é
 * quem entrou — o morador. É o caso dele que este teste mede.
 */

const EXECUCAO = randomUUID().slice(0, 8);

const ATA_COM_ANEXO =
  "Documentos do Condomínio/Atas de Assembleia/22115 - BREEZE AGE 04.02.2026 site.pdf";

async function publica(
  editora: Awaited<ReturnType<typeof editoraComSegundoFator>>,
  caminho: string,
  tipo: string,
  titulo: string,
  visibilidade: string,
): Promise<string> {
  const id = randomUUID();
  const storagePath = `anexo-${EXECUCAO}-${id}.pdf`;
  await enviaParaStorage(caminho, storagePath);

  const criacao = await criaDocumento(editora.aal2, {
    id,
    tipo,
    titulo,
    storage_bucket: "documentos",
    storage_path: storagePath,
    status: "pendente",
    visibilidade,
  });
  expect(criacao.ok).toBe(true);

  await sql(
    `select job.enfileirar('hash_dedupe','${id}'::uuid,'hash_dedupe:${id}:v1','{}'::jsonb,100)`,
  );
  await drenaFila();
  await sql(
    `update public.documentos
        set status = 'publicado', publicado_em = now(), publicado_por = '${editora.pessoaId}'
      where id = '${id}'`,
  );
  return id;
}

test.describe("anexo replicado", () => {
  test.describe.configure({ mode: "serial", timeout: 300_000 });

  test("a mesma regra em dois documentos vira um resultado, com o normativo na frente", async ({
    page,
  }) => {
    const editora = await editoraComSegundoFator(`anexo-${EXECUCAO}`);

    const tituloAta = `Ata AGE com anexo ${EXECUCAO}`;
    const tituloRegimento = `Regimento canônico ${EXECUCAO}`;

    // `autenticado`: o schema recusa ata pública, e é isso que faz a duplicata
    // ser um problema de quem entrou, não do anônimo.
    await publica(editora, ATA_COM_ANEXO, "ata_assembleia", tituloAta, "autenticado");
    await publica(editora, REGIMENTO, "regimento", tituloRegimento, "publico");

    // Entra pelo e-mail, como o morador entraria.
    await page.goto("/entrar");
    await page.getByLabel(/CPF ou e-mail/i).fill(editora.email);
    await page.getByRole("button", { name: /Receber link/i }).click();
    const link = await linkDoUltimoEmail(editora.email);
    expect(link).not.toBeNull();
    await page.goto(link!);

    await page.goto("/buscar?q=animais+dom%C3%A9sticos");

    // O Regimento é o canônico: a ata prova que a regra foi aprovada, mas quem
    // diz a regra é o regimento. Citar a ata manda o morador procurar no lugar
    // errado.
    await expect(page.getByRole("link", { name: new RegExp(tituloRegimento) }).first())
      .toBeVisible();

    // A cópia não some — vira nota no resultado que sobreviveu.
    await expect(page.getByText(/O mesmo texto aparece também em/i).first()).toBeVisible();
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
         (select id from public.pessoas where email like 'anexo-${EXECUCAO}-%');
       delete from public.pessoas where email like 'anexo-${EXECUCAO}-%';
       delete from auth.users where email like 'anexo-${EXECUCAO}-%';`,
    );
  });
});
