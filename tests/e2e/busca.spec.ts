import { randomUUID } from "node:crypto";

import { expect, test } from "@playwright/test";

import {
  buscaComo,
  criaDocumento,
  drenaFila,
  editoraComSegundoFator,
  enviaParaStorage,
  REGIMENTO,
  sql,
} from "./apoio";

/**
 * Corte C6 — busca léxica sobre o acervo real, com a RLS no meio.
 *
 * O caso que importa aqui não é "achou". É **quem** acha: a busca é o caminho
 * mais fácil para um vazamento, porque devolve trecho de texto de qualquer
 * documento que o banco deixar passar. Por isso os dois primeiros testes são
 * sobre o anônimo, e não sobre a editora.
 */

const EXECUCAO = randomUUID().slice(0, 8);

/**
 * Ingere o Regimento uma vez e devolve o documento.
 *
 * Uma vez só, e os testes seguintes mudam o status dele: o pipeline detecta
 * duplicata por `sha256`, então ingerir o mesmo arquivo duas vezes não produz um
 * segundo documento indexado — produz um documento marcado como duplicata,
 * corretamente. O teste vive com a regra do produto em vez de contorná-la.
 */
async function ingereRegimento(publicado: boolean): Promise<{ id: string; titulo: string }> {
  const editora = await editoraComSegundoFator(`busca-${EXECUCAO}`);
  const id = randomUUID();
  const titulo = `Regimento ${publicado ? "publicado" : "em revisão"} ${EXECUCAO}-${id.slice(0, 4)}`;
  const storagePath = `busca-${EXECUCAO}-${id}.pdf`;

  await enviaParaStorage(REGIMENTO, storagePath);
  const criacao = await criaDocumento(editora.aal2, {
    id,
    tipo: "regimento",
    titulo,
    storage_bucket: "documentos",
    storage_path: storagePath,
    status: "pendente",
    visibilidade: "publico",
  });
  expect(criacao.ok).toBe(true);

  await sql(
    `select job.enfileirar('hash_dedupe','${id}'::uuid,'hash_dedupe:${id}:v1','{}'::jsonb,100)`,
  );
  await drenaFila();

  if (publicado) {
    // Publicar é ato da editora, e o schema exige quem e quando.
    await sql(
      `update public.documentos
          set status = 'publicado', publicado_em = now(), publicado_por = '${editora.pessoaId}'
        where id = '${id}'`,
    );
  }

  return { id, titulo };
}

test.describe("busca", () => {
  test.describe.configure({ mode: "serial", timeout: 240_000 });

  let documento: { id: string; titulo: string };
  let editora: Awaited<ReturnType<typeof editoraComSegundoFator>>;

  test.beforeAll(async () => {
    editora = await editoraComSegundoFator(`busca-${EXECUCAO}`);
    documento = await ingereRegimento(true);
  });

  test("o anônimo acha o regimento publicado, com capítulo e trecho literal", async () => {
    const { titulo } = documento;

    const resultados = await buscaComo(null, "animais domésticos");

    const meus = resultados.filter((r) => r.titulo === titulo);
    expect(meus.length).toBeGreaterThan(0);

    // O capítulo viaja com o resultado: sem ele, "Artigo 1º" apontaria para 24
    // lugares diferentes deste mesmo documento.
    expect(meus.some((r) => r.secao?.includes("ANIMAIS"))).toBe(true);
    // O trecho vem marcado — é o resultado primário na tela, não um resumo.
    expect(meus.some((r) => r.trecho.includes("<mark>"))).toBe(true);
  });

  test("o anônimo NÃO acha documento que ainda não foi publicado", async () => {
    const { id, titulo } = documento;
    await sql(
      `update public.documentos set status = 'em_revisao' where id = '${id}'`,
    );

    const resultados = await buscaComo(null, "animais domésticos");

    // Mesmo sendo tipo público, o documento em conferência não existe para quem
    // não entrou. Quem nega é a RLS: a função de busca é `security invoker` e não
    // tem privilégio próprio.
    expect(resultados.some((r) => r.titulo === titulo)).toBe(false);
  });

  test("a editora acha o que ainda está em conferência — é o trabalho dela", async () => {
    // Mesmo documento do teste anterior, ainda em `em_revisao`.
    const resultados = await buscaComo(editora.aal2, "animais domésticos");
    expect(resultados.some((r) => r.titulo === documento.titulo)).toBe(true);
  });

  test("consulta sem resposta devolve vazio, não erro", async () => {
    // Sintaxe que o `websearch_to_tsquery` poderia recusar. Busca que quebra a
    // tela é pior que busca que não acha.
    expect(await buscaComo(null, '"aspas sem fechar AND ((')).toEqual([]);
    expect(await buscaComo(null, "termoquenaoexisteemlugarnenhum")).toEqual([]);
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
         (select id from public.pessoas where email like 'busca-${EXECUCAO}-%');
       delete from public.pessoas where email like 'busca-${EXECUCAO}-%';
       delete from auth.users where email like 'busca-${EXECUCAO}-%';`,
    );
  });
});
