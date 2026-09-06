import { createHash, randomUUID } from "node:crypto";
import { readFile } from "node:fs/promises";

import { expect, test } from "@playwright/test";

import {
  criaDocumento,
  drenaFila,
  editoraComSegundoFator,
  enviaParaStorage,
  REGIMENTO,
  sql,
} from "./apoio";

/**
 * Corte C2 — ingestão de um documento, do arquivo ao chunk, contra o banco real.
 *
 * O que este teste prova, e que nenhum unitário prova: que a **editora
 * autenticada** consegue criar o documento (a RLS exige `editor` com `aal2`),
 * que o worker atravessa os estágios, e que o texto chega ao banco com página e
 * seção. Também prova o contrário: a mesma criação é **recusada** quando a
 * sessão não tem segundo fator — porque quem decide é o banco, não a tela.
 *
 * Não usa navegador; usa a API como o script de backfill usa.
 */

const EXECUCAO = randomUUID().slice(0, 8);

test.describe("ingestão", () => {
  test.describe.configure({ mode: "serial", timeout: 240_000 });

  test("o Regimento entra no acervo com páginas, texto e seção", async () => {
    const editora = await editoraComSegundoFator(`ingestao-${EXECUCAO}`);
    const conteudo = await readFile(REGIMENTO);
    const id = randomUUID();
    const storagePath = `teste-${EXECUCAO}-${id}.pdf`;

    await enviaParaStorage(REGIMENTO, storagePath);

    // A sessão SEM segundo fator é editora no cadastro e moradora na prática.
    const semSegundoFator = await criaDocumento(editora.aal1, {
      id: randomUUID(),
      tipo: "regimento",
      titulo: `Recusado ${EXECUCAO}`,
      storage_bucket: "documentos",
      storage_path: `recusado-${storagePath}`,
      status: "pendente",
    });
    expect(semSegundoFator.status).toBeGreaterThanOrEqual(400);

    const criacao = await criaDocumento(editora.aal2, {
      id,
      tipo: "regimento",
      titulo: `Regimento Interno (teste ${EXECUCAO})`,
      storage_bucket: "documentos",
      storage_path: storagePath,
      status: "pendente",
      visibilidade: "publico",
    });
    if (!criacao.ok) {
      throw new Error(`criação recusada: ${criacao.status} ${await criacao.text()}`);
    }

    await sql(
      `select job.enfileirar('hash_dedupe','${id}'::uuid,'hash_dedupe:${id}:v1','{}'::jsonb,100)`,
    );
    await drenaFila();

    const paginas = Number(
      await sql(`select count(*) from public.documento_paginas where documento_id = '${id}'`),
    );
    expect(paginas).toBe(23);

    // O hash é do arquivo que realmente chegou, calculado pelo worker — nunca
    // aceito do cliente (ADR-0004).
    const sha = await sql(
      `select encode(sha256, 'hex') from public.documentos where id = '${id}'`,
    );
    expect(sha).toBe(createHash("sha256").update(conteudo).digest("hex"));

    // O tamanho é lido antes de o PDF ser aberto: o pdf.js desacopla o buffer que
    // recebe, e ler `byteLength` depois grava zero — foi o que o check do schema
    // pegou na primeira execução real deste pipeline.
    const bytes = Number(await sql(`select bytes from public.documentos where id = '${id}'`));
    expect(bytes).toBe(conteudo.byteLength);

    // `em_revisao`, nunca `publicado`: quem publica é uma pessoa (SPEC §3.5).
    expect(await sql(`select status from public.documentos where id = '${id}'`)).toBe(
      "em_revisao",
    );

    const chunks = Number(
      await sql(`select count(*) from public.chunks where documento_id = '${id}'`),
    );
    expect(chunks).toBeGreaterThan(10);

    const comSecao = Number(
      await sql(
        `select count(*) from public.chunks where documento_id = '${id}' and secao is not null`,
      ),
    );
    expect(comSecao).toBeGreaterThan(chunks / 2);

    const texto = await sql(
      `select left(texto, 60) from public.documento_paginas
        where documento_id = '${id}' and pagina = 1`,
    );
    expect(texto).toContain("REGULAMENTO INTERNO");

    // `tsv` é coluna gerada: se a configuração `public.pt_br` não estivesse no
    // lugar, o insert do chunk teria falhado. Este assert confirma o efeito —
    // "sindico" acha "Síndico" porque a configuração encadeia `unaccent`.
    const achou = Number(
      await sql(
        `select count(*) from public.chunks
          where documento_id = '${id}'
            and tsv @@ websearch_to_tsquery('public.pt_br', 'sindico')`,
      ),
    );
    expect(achou).toBeGreaterThan(0);
  });

  test("o mesmo arquivo de novo é detectado como duplicata, não indexado duas vezes", async () => {
    const editora = await editoraComSegundoFator(`ingestao-${EXECUCAO}`);
    const id = randomUUID();
    const storagePath = `dup-${EXECUCAO}-${id}.pdf`;

    await enviaParaStorage(REGIMENTO, storagePath);
    const criacao = await criaDocumento(editora.aal2, {
      id,
      tipo: "regimento",
      titulo: `Duplicata (teste ${EXECUCAO})`,
      storage_bucket: "documentos",
      storage_path: storagePath,
      status: "pendente",
    });
    expect(criacao.ok).toBe(true);

    await sql(
      `select job.enfileirar('hash_dedupe','${id}'::uuid,'hash_dedupe:${id}:v1','{}'::jsonb,100)`,
    );
    await drenaFila();

    const status = await sql(
      `select status || '|' || coalesce(erro_detalhe,'') from public.documentos where id = '${id}'`,
    );
    expect(status).toContain("erro|");
    expect(status).toContain("idêntico");

    // Duplicata não gera página nem chunk: o trabalho é evitado, não desfeito.
    const paginas = Number(
      await sql(`select count(*) from public.documento_paginas where documento_id = '${id}'`),
    );
    expect(paginas).toBe(0);
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
         (select id from public.pessoas where email like 'ingestao-${EXECUCAO}-%');
       delete from public.pessoas where email like 'ingestao-${EXECUCAO}-%';
       delete from auth.users where email like 'ingestao-${EXECUCAO}-%';`,
    );
  });
});
