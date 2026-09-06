import { describe, expect, it } from "vitest";

import {
  chunkiza,
  estimaTokens,
  OPCOES_PADRAO,
  type PaginaParaChunk,
} from "@/lib/ingestao/chunker";

function paginaDe(pagina: number, linhas: number, visibilidade: string | null = null): PaginaParaChunk {
  const texto = Array.from(
    { length: linhas },
    (_, i) => `Linha ${i} da página ${pagina} com texto suficiente para somar tokens de verdade.`,
  ).join("\n");
  return { pagina, texto, visibilidade };
}

describe("chunkiza", () => {
  it("respeita o teto de tokens e mantém a ordem", () => {
    const chunks = chunkiza([paginaDe(1, 200), paginaDe(2, 200)], "autenticado");

    expect(chunks.length).toBeGreaterThan(1);
    expect(chunks.map((c) => c.ordem)).toEqual(chunks.map((_, i) => i));
    for (const chunk of chunks) {
      expect(chunk.tokens).toBeLessThanOrEqual(OPCOES_PADRAO.tokensMaximos);
    }
  });

  it("rastreia a página de início e de fim — é o que a citação mostra", () => {
    const chunks = chunkiza([paginaDe(1, 60), paginaDe(2, 60), paginaDe(3, 60)], "autenticado");

    for (const chunk of chunks) {
      expect(chunk.paginaIni).toBeLessThanOrEqual(chunk.paginaFim);
      expect(chunk.paginaIni).toBeGreaterThanOrEqual(1);
      expect(chunk.paginaFim).toBeLessThanOrEqual(3);
    }
    expect(chunks[0].paginaIni).toBe(1);
    expect(chunks.at(-1)!.paginaFim).toBe(3);
  });

  it("NUNCA costura páginas de visibilidades diferentes no mesmo chunk", () => {
    // O caso real: ata autenticada (págs. 1–2) que embute o Regimento público
    // (págs. 3–4) como anexo. Com 15% de sobreposição, um chunker ingênuo cola
    // o fim da ata no começo do regimento — e a busca pública passa a devolver
    // texto autenticado sem ninguém ter mudado policy nenhuma.
    const paginas = [
      paginaDe(1, 40),
      paginaDe(2, 40),
      paginaDe(3, 40, "publico"),
      paginaDe(4, 40, "publico"),
    ];

    const chunks = chunkiza(paginas, "autenticado");

    for (const chunk of chunks) {
      const paginasDoChunk = [chunk.paginaIni, chunk.paginaFim];
      const atravessa =
        paginasDoChunk.some((p) => p <= 2) && paginasDoChunk.some((p) => p >= 3);
      expect(atravessa).toBe(false);
    }
    expect(chunks.some((c) => c.visibilidade === "publico")).toBe(true);
    expect(chunks.some((c) => c.visibilidade === "autenticado")).toBe(true);
  });

  it("nenhum chunk atravessa capítulo — a citação depende disso", () => {
    // O Regimento do Breeze tem 24 capítulos e REINICIA a numeração de artigo em
    // cada um: existem 24 "Artigo 1º". Um chunk que começasse no Cap. V e
    // terminasse no Cap. VII carregaria o rótulo do primeiro e citaria o texto do
    // outro — apontando para um artigo que existe e diz outra coisa.
    const corpo = Array.from(
      { length: 20 },
      (_, i) => `Artigo ${i + 1}º - Regra do capítulo com texto longo o suficiente para somar tokens.`,
    ).join("\n");
    const paginas: PaginaParaChunk[] = [
      { pagina: 1, texto: `I. CAPÍTULO – DISPOSIÇÕES GERAIS\n${corpo}`, visibilidade: null },
      { pagina: 2, texto: `II. CAPÍTULO – PORTARIA\n${corpo}`, visibilidade: null },
      { pagina: 3, texto: `III. CAPÍTULO – PISCINA\n${corpo}`, visibilidade: null },
    ];

    const chunks = chunkiza(paginas, "publico");

    expect(new Set(chunks.map((c) => c.secao)).size).toBe(3);
    for (const chunk of chunks) {
      const titulosDentro = chunk.texto
        .split("\n")
        .filter((l) => /CAP[IÍ]TULO/.test(l));
      // No máximo um título de capítulo por chunk: o do próprio chunk.
      expect(titulosDentro.length).toBeLessThanOrEqual(1);
      if (titulosDentro.length === 1) expect(chunk.secao).toBe(titulosDentro[0]);
    }
  });

  it("prefere cortar em começo de artigo", () => {
    const corpo = Array.from(
      { length: 30 },
      (_, i) => `Texto corrido número ${i} com tamanho suficiente para acumular tokens no chunk.`,
    ).join("\n");
    const paginas: PaginaParaChunk[] = [
      {
        pagina: 1,
        texto: `Art. 1º Primeira regra.\n${corpo}\nArt. 2º Segunda regra.\n${corpo}\nArt. 3º Terceira regra.\n${corpo}`,
        visibilidade: null,
      },
    ];

    const chunks = chunkiza(paginas, "publico");
    // Do segundo chunk em diante, o começo deve cair num artigo (ou na
    // sobreposição que o precede), não no meio de uma frase qualquer.
    expect(chunks.length).toBeGreaterThan(1);
    expect(chunks.some((c) => /^Art\. \d/.test(c.texto))).toBe(true);
  });

  it("sobrepõe o suficiente para a frase de fronteira não se perder", () => {
    const chunks = chunkiza([paginaDe(1, 400)], "autenticado");
    expect(chunks.length).toBeGreaterThan(1);

    const fimDoPrimeiro = chunks[0].texto.split("\n").at(-1)!;
    expect(chunks[1].texto).toContain(fimDoPrimeiro);
  });

  it("não entra em laço infinito com bloco maior que o teto", () => {
    const gigante = "palavra ".repeat(4000);
    const chunks = chunkiza([{ pagina: 1, texto: gigante, visibilidade: null }], "publico");
    expect(chunks).toHaveLength(1);
    expect(chunks[0].tokens).toBeGreaterThan(OPCOES_PADRAO.tokensMaximos);
  });

  it("página vazia não vira chunk vazio", () => {
    const chunks = chunkiza(
      [{ pagina: 1, texto: "   \n\n  ", visibilidade: null }],
      "publico",
    );
    expect(chunks).toHaveLength(0);
  });
});

describe("estimaTokens", () => {
  it("cresce com o texto e ignora espaço nas pontas", () => {
    expect(estimaTokens("  ")).toBe(0);
    expect(estimaTokens("abcd")).toBe(1);
    expect(estimaTokens("a".repeat(400))).toBe(100);
  });
});
