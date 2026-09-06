import { describe, expect, it } from "vitest";

import {
  assinatura,
  deduplica,
  semelhanca,
  type Deduplicavel,
} from "@/lib/busca/deduplica";

const TRECHO_DO_REGIMENTO =
  "V. CAPÍTULO – ANIMAIS DOMÉSTICOS\n" +
  "Artigo 1º - Serão permitidos animais domésticos de porte pequeno, médio e grande, e a " +
  "permanência é proibida em qualquer área não destinada para este fim. As raças consideradas " +
  "ferozes devem transitar, além da coleira, com focinheiras obrigatoriamente.";

/** A mesma regra, como ela aparece dentro da ata que anexou o regimento. */
const MESMO_TRECHO_DENTRO_DA_ATA =
  "ANIMAIS DOMÉSTICOS\n" +
  "Artigo 1º - Serão permitidos animais domésticos de porte pequeno, médio e grande e a " +
  "permanência é proibida em qualquer área não destinada para este fim. As raças consideradas " +
  "ferozes devem transitar além da coleira com focinheiras obrigatoriamente.";

function item(parcial: Partial<Deduplicavel>): Deduplicavel {
  return {
    chunkId: crypto.randomUUID(),
    documentoId: crypto.randomUUID(),
    titulo: "documento",
    tipo: "outros",
    texto: "",
    rank: 0.1,
    ...parcial,
  };
}

describe("deduplica", () => {
  it("funde as duas cópias e mantém a normativa, mesmo com rank pior", () => {
    // O caso real: a ata da AGE de 04.02.2026 embute o Regimento inteiro. A ata
    // prova que a regra foi aprovada; quem diz a regra é o Regimento — citar a
    // ata manda o morador procurar no lugar errado.
    const daAta = item({
      titulo: "BREEZE AGE 04.02.2026",
      tipo: "ata_assembleia",
      texto: MESMO_TRECHO_DENTRO_DA_ATA,
      rank: 0.9,
    });
    const doRegimento = item({
      titulo: "Regimento Interno",
      tipo: "regimento",
      texto: TRECHO_DO_REGIMENTO,
      rank: 0.2,
    });

    const saida = deduplica([daAta, doRegimento]);

    expect(saida).toHaveLength(1);
    expect(saida[0].resultado.tipo).toBe("regimento");
    expect(saida[0].tambemEm).toEqual([
      { documentoId: daAta.documentoId, titulo: "BREEZE AGE 04.02.2026" },
    ]);
  });

  it("não esconde a cópia: ela vira nota no resultado que sobreviveu", () => {
    const saida = deduplica([
      item({ tipo: "regimento", titulo: "Regimento", texto: TRECHO_DO_REGIMENTO }),
      item({ tipo: "ata_assembleia", titulo: "Ata", texto: MESMO_TRECHO_DENTRO_DA_ATA }),
    ]);
    expect(saida[0].tambemEm.map((t) => t.titulo)).toEqual(["Ata"]);
  });

  it("não funde textos que só falam do mesmo assunto", () => {
    const a = item({
      tipo: "regimento",
      texto:
        "Artigo 3º - A churrasqueira deve ser reservada com antecedência mínima de 48 horas junto à administração.",
    });
    const b = item({
      tipo: "ata_assembleia",
      texto:
        "Artigo 7º - O uso da churrasqueira em feriados obedece a rodízio entre as unidades interessadas.",
    });
    expect(deduplica([a, b])).toHaveLength(2);
  });

  it("não funde repetição dentro do MESMO documento", () => {
    // Sobreposição de chunk é estrutura do documento, não anexo replicado.
    const documentoId = crypto.randomUUID();
    const saida = deduplica([
      item({ documentoId, tipo: "regimento", texto: TRECHO_DO_REGIMENTO }),
      item({ documentoId, tipo: "regimento", texto: TRECHO_DO_REGIMENTO }),
    ]);
    expect(saida).toHaveLength(2);
  });

  it("preserva a ordem de quem sobreviveu", () => {
    const primeiro = item({ tipo: "balancete", texto: "receita ordinária de janeiro de 2026" });
    const segundo = item({ tipo: "comunicado", texto: "reunião sobre o sistema de segurança" });
    const saida = deduplica([primeiro, segundo]);
    expect(saida.map((s) => s.resultado.chunkId)).toEqual([
      primeiro.chunkId,
      segundo.chunkId,
    ]);
  });
});

describe("semelhanca", () => {
  it("é 1 para texto idêntico e 0 para texto sem relação", () => {
    expect(semelhanca(assinatura(TRECHO_DO_REGIMENTO), assinatura(TRECHO_DO_REGIMENTO))).toBe(1);
    expect(
      semelhanca(
        assinatura("o portão social permanece fechado durante a noite"),
        assinatura("a taxa de administração é paga mensalmente à administradora"),
      ),
    ).toBe(0);
  });

  it("ignora acento e pontuação, que é onde as duas cópias divergem", () => {
    expect(
      semelhanca(assinatura(TRECHO_DO_REGIMENTO), assinatura(MESMO_TRECHO_DENTRO_DA_ATA)),
    ).toBeGreaterThan(0.6);
  });
});
