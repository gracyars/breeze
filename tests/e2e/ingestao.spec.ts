import { createHash, randomUUID } from "node:crypto";
import { readFile } from "node:fs/promises";

import { expect, test } from "@playwright/test";

import {
  CONVENCAO,
  criaDocumento,
  PROCEDIMENTOS_REFORMA,
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

  test("reprocessar documento publicado não o derruba da vista do morador", async () => {
    // O ADR-0026 separa `indexado_em` de `status` justamente para que "fora da
    // busca" não signifique "fora do acervo". O worker quase desfez isso por
    // outra porta: o estágio de chunking marcava `em_revisao` sem olhar o status
    // anterior, então reclassificar uma página de documento publicado o fazia
    // sumir para o morador até a fila ser drenada.
    const editora = await editoraComSegundoFator(`reproc-${EXECUCAO}`);
    const id = randomUUID();
    const storagePath = `reproc-${EXECUCAO}-${id}.pdf`;

    await enviaParaStorage(PROCEDIMENTOS_REFORMA, storagePath);
    const criacao = await criaDocumento(editora.aal2, {
      id,
      tipo: "documentacao_obra",
      titulo: `Procedimentos de reforma ${EXECUCAO}`,
      storage_bucket: "documentos",
      storage_path: storagePath,
      status: "pendente",
      // `autenticado`, não `publico`: a visibilidade do documento é o **piso**, e
      // a página só pode ser igual ou mais permissiva (ADR-0019). Num documento
      // já público não existe reclassificação que mude alguma coisa — foi assim
      // que a primeira versão deste teste passou verde com o defeito presente.
      visibilidade: "autenticado",
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

    // Trava a lacuna que fez a primeira versão deste teste medir um documento
    // vazio: se a deduplicação recusar o arquivo, não há chunk nenhum e todo o
    // resto do teste passa sem exercitar nada.
    const chunksAntes = Number(
      await sql(`select count(*) from public.chunks where documento_id = '${id}'`),
    );
    expect(chunksAntes).toBeGreaterThan(0);
    expect(
      await sql(`select coalesce(indexado_em::text,'null') from public.documentos where id = '${id}'`),
    ).not.toBe("null");

    // Reclassificar a página para MAIS permissiva muda o nível efetivo: os chunks
    // que a intersectam são apagados e o documento é reenfileirado (ADR-0026).
    await sql(
      `update public.documento_paginas set visibilidade = 'publico'
        where documento_id = '${id}' and pagina = 14`,
    );

    // Durante a invalidação, o documento continua publicado — quem sinaliza
    // "fora da busca" é `indexado_em`, não o status.
    expect(await sql(`select status from public.documentos where id = '${id}'`)).toBe(
      "publicado",
    );
    expect(
      await sql(`select coalesce(indexado_em::text, 'null') from public.documentos where id = '${id}'`),
    ).toBe("null");
    expect(
      Number(
        await sql(
          `select count(*) from job.fila
            where payload->>'documento_id' = '${id}' and status = 'pendente'`,
        ),
      ),
    ).toBeGreaterThan(0);

    await drenaFila();

    // Depois de reindexar, continua publicado — e volta a ter chunks.
    expect(await sql(`select status from public.documentos where id = '${id}'`)).toBe(
      "publicado",
    );
    const chunks = Number(
      await sql(`select count(*) from public.chunks where documento_id = '${id}'`),
    );
    expect(chunks).toBeGreaterThan(0);
    expect(
      await sql(`select coalesce(indexado_em::text,'null') from public.documentos where id = '${id}'`),
    ).not.toBe("null");
  });

  test("a Convenção escaneada passa pelo OCR e fica citável", async () => {
    // O único documento público do acervo é imagem pura: 18 páginas, zero
    // caractere nativo. Sem este caminho, o texto normativo-mãe do condomínio
    // fica fora da busca — era o bloqueio que a sonda C0 existiu para destravar.
    // Leva ~1 min: o OCR roda página a página, na CPU desta máquina.
    test.setTimeout(300_000);

    const editora = await editoraComSegundoFator(`ocr-${EXECUCAO}`);
    const id = randomUUID();
    const storagePath = `conv-${EXECUCAO}-${id}.pdf`;

    await enviaParaStorage(CONVENCAO, storagePath);
    const criacao = await criaDocumento(editora.aal2, {
      id,
      tipo: "convencao",
      titulo: `Convenção (teste ${EXECUCAO})`,
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

    // Toda página veio do OCR: a extração nativa devolveu vazio em todas as 18,
    // que é o único caso em que o OCR dispara sozinho (ADR-0024).
    const porFonte = await sql(
      `select string_agg(fonte_texto || '=' || n, ',' order by fonte_texto)
         from (select fonte_texto, count(*) n from public.documento_paginas
                where documento_id = '${id}' group by 1) t`,
    );
    expect(porFonte).toBe("ocr=18");
    expect(await sql(`select ocr_aplicado from public.documentos where id = '${id}'`)).toBe("t");

    const confianca = Number(
      await sql(
        `select round(avg(confianca_ocr), 3) from public.documento_paginas where documento_id = '${id}'`,
      ),
    );
    // Gatilho G1 do ADR-0024: abaixo de 0,90 a decisão de usar OCR local se
    // reabre e a API paga volta à mesa.
    expect(confianca).toBeGreaterThan(0.9);

    // A passagem de quórum é a que um morador citaria numa assembleia.
    const quorum = Number(
      await sql(
        `select count(*) from public.chunks
          where documento_id = '${id}'
            and tsv @@ websearch_to_tsquery('public.pt_br', 'quórum instalação')`,
      ),
    );
    expect(quorum).toBeGreaterThan(0);

    // O normalizador de marcador rodou dentro do pipeline: a sequência de
    // subitens da página 12 sai correta, e é o marcador que identifica o item
    // citado numa convenção que não é articulada.
    const marcadores = await sql(
      `select string_agg(m[1], ',')
         from (select regexp_match(linha, '^((?:i|v|x)+)\\.') m
                 from (select unnest(string_to_array(texto, chr(10))) linha
                         from public.documento_paginas
                        where documento_id = '${id}' and pagina = 12) l
                where linha ~ '^(i|v|x)+\\.') t`,
    );
    expect(marcadores).toContain("i,ii,iii,iv,v,vi");
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
         (select id from public.pessoas
           where email like 'ingestao-${EXECUCAO}-%'
              or email like 'ocr-${EXECUCAO}-%'
              or email like 'reproc-${EXECUCAO}-%');
       delete from public.pessoas
         where email like 'ingestao-${EXECUCAO}-%'
            or email like 'ocr-${EXECUCAO}-%'
            or email like 'reproc-${EXECUCAO}-%';
       delete from auth.users
         where email like 'ingestao-${EXECUCAO}-%'
            or email like 'ocr-${EXECUCAO}-%'
            or email like 'reproc-${EXECUCAO}-%';`,
    );
  });
});
