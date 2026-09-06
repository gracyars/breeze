import { describe, expect, it } from "vitest";

import {
  caracteresUteis,
  exigeOcrAutomatico,
  proporOcrNaConferencia,
  razaoIlegivel,
  type PaginaExtraida,
} from "@/lib/ingestao/extracao";

function pagina(parcial: Partial<PaginaExtraida>): PaginaExtraida {
  return {
    pagina: 1,
    textoNativo: "",
    texto: "",
    fonteTexto: "nativo",
    caracteresUteis: 0,
    razaoIlegivel: 0,
    ...parcial,
  };
}

describe("caracteresUteis", () => {
  it("não conta o pontilhado de sumário", () => {
    // Um dos 6 falsos positivos da heurística antiga sobre o acervo real: sumário
    // com pontilhado tem centenas de caracteres e quase nenhum texto.
    const sumario = "Capítulo I ............................................ 3";
    expect(caracteresUteis(sumario)).toBeLessThan(sumario.length - 30);
  });

  it("não conta espaço repetido de capa espaçada", () => {
    expect(caracteresUteis("B   R   E   E   Z   E")).toBe("B R E E Z E".length);
  });
});

describe("razaoIlegivel", () => {
  it("é baixa em português normal", () => {
    const texto =
      "O condômino que aumentar as despesas comuns, por sua exclusiva conveniência, pagará o excesso que motivar.";
    expect(razaoIlegivel(texto)).toBeLessThan(0.1);
  });

  it("sobe com sopa de consoante — a assinatura de OCR ruim herdado", () => {
    expect(razaoIlegivel("hjkl mnbvc xzwqr tnghs prstk")).toBeGreaterThan(0.5);
  });

  it("não se assusta com tabela de números", () => {
    // Balancete é coluna de número; não é ilegível, é denso.
    expect(razaoIlegivel("1.234,56 2.345,67 3.456,78 4.567,89")).toBeLessThan(0.2);
  });
});

describe("disparo de OCR", () => {
  it("dispara sozinho só quando não há o que degradar", () => {
    expect(exigeOcrAutomatico(pagina({ fonteTexto: "vazio" }))).toBe(true);
    expect(
      exigeOcrAutomatico(pagina({ fonteTexto: "nativo", razaoIlegivel: 0.9 })),
    ).toBe(false);
  });

  it("página com texto suspeito vira PERGUNTA, nunca ação", () => {
    // Com OCR local o custo do falso positivo deixou de ser dinheiro e passou a
    // ser sobrescrever texto nativo correto — pior. Quem decide é a editora.
    const suspeita = pagina({ fonteTexto: "nativo", razaoIlegivel: 0.8 });
    expect(exigeOcrAutomatico(suspeita)).toBe(false);
    expect(proporOcrNaConferencia(suspeita)).toBe(true);
  });

  it("página boa não incomoda a conferência", () => {
    expect(
      proporOcrNaConferencia(pagina({ fonteTexto: "nativo", razaoIlegivel: 0.05 })),
    ).toBe(false);
  });
});
