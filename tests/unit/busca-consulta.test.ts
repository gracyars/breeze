import { describe, expect, it } from "vitest";

import {
  expandeSinonimos,
  normaliza,
  pareceIdentificador,
  type Sinonimo,
} from "@/lib/busca/consulta";

/** Os sinônimos reais do seed (SPEC §4). */
const SINONIMOS: Sinonimo[] = [
  { termoNormalizado: "taxa condominial", expansoes: ["cota", "rateio", "cota condominial"] },
  { termoNormalizado: "fundo de reserva", expansoes: ["FR"] },
  { termoNormalizado: "prestacao de contas", expansoes: ["balancete"] },
  { termoNormalizado: "age", expansoes: ["assembleia extraordinária"] },
];

describe("expandeSinonimos", () => {
  it("troca o termo do morador pelo vocabulário do documento", () => {
    const saida = expandeSinonimos("qual o valor da taxa condominial", SINONIMOS);
    expect(saida).toContain("cota");
    expect(saida).toContain("rateio");
    expect(saida).toContain("OR");
  });

  it("casa mesmo sem acento — o morador não digita acento na pressa", () => {
    const saida = expandeSinonimos("onde vejo a prestação de contas", SINONIMOS);
    expect(saida).toContain("balancete");
  });

  it("expande o termo mais longo primeiro", () => {
    // "prestação de contas" tem de casar como expressão, não deixar "contas"
    // sozinha casar antes e quebrar a expressão no meio.
    const saida = expandeSinonimos("prestação de contas de janeiro", SINONIMOS);
    expect(saida).toContain("balancete");
    expect(saida.match(/OR/g)?.length).toBe(1);
  });

  it("NÃO expande o que está entre aspas", () => {
    // Quem digita aspas está pedindo literal. Expandir por baixo do pano quebra
    // exatamente a busca por identificador exato, que é metade do problema.
    const saida = expandeSinonimos('"taxa condominial" no regimento', SINONIMOS);
    expect(saida).toContain('"taxa condominial"');
    expect(saida).not.toContain("rateio");
  });

  it("deixa a consulta intacta quando nada casa", () => {
    expect(expandeSinonimos("cachorro no elevador", SINONIMOS)).toBe(
      "cachorro no elevador",
    );
  });
});

describe("pareceIdentificador", () => {
  it("reconhece referência legal, valor e sigla de assembleia", () => {
    expect(pareceIdentificador("art. 12")).toBe(true);
    expect(pareceIdentificador("Artigo 5 do regimento")).toBe(true);
    expect(pareceIdentificador("R$ 43.200")).toBe(true);
    expect(pareceIdentificador("AGE de março")).toBe(true);
  });

  it("não confunde pergunta em linguagem natural com identificador", () => {
    expect(pareceIdentificador("posso ter cachorro?")).toBe(false);
    expect(pareceIdentificador("quem paga o conserto do portão")).toBe(false);
  });
});

describe("normaliza", () => {
  it("tira acento e caixa", () => {
    expect(normaliza("  Síndico ")).toBe("sindico");
  });
});
