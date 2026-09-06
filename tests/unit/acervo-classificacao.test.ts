import { describe, expect, it } from "vitest";

import {
  classifica,
  competenciaDoNome,
  dataDoNome,
  tituloDoNome,
} from "@/lib/acervo/classificacao";

/**
 * Todos os nomes deste arquivo são **reais**: saíram dos 43 PDFs em
 * `Documentos do Condomínio/`. Testar a regra contra nome inventado provaria que
 * ela funciona no acervo que eu imaginei, não no que existe.
 */
describe("classifica", () => {
  it("trata lembrete de assembleia como convocação, não como comunicado", () => {
    // A armadilha nomeada pelo `guardiao-dominio`: convocação tem efeito
    // jurídico (CC art. 1.354) e o rótulo do arquivo não decide.
    const r = classifica(
      "Documentos do Condomínio/Comunicados /2215 - LEMBRETE –  ASSEMBLEIA GERAL EXTRAORDINÁRIA – 04.02.2026.pdf",
    );
    expect(r.tipo).toBe("edital_convocacao");
    expect(r.dataDocumento).toBe("2026-02-04");
  });

  it("separa resumo de assembleia da ata — e o resumo vem antes na regra", () => {
    // Se a regra de ata viesse primeiro, o resumo viraria ata e passaria a poder
    // ancorar deliberação. O morador lê o resumo antes da ata registrada.
    expect(
      classifica("Documentos do Condomínio/Comunicados /RESUMO ASSEMBLEIA 04.02.2026.pdf").tipo,
    ).toBe("resumo_assembleia");
    expect(
      classifica("Documentos do Condomínio/Atas de Assembleia/22115 - BREEZE AGE 04.02.2026 site.pdf")
        .tipo,
    ).toBe("ata_assembleia");
  });

  it("reconhece os dois documentos públicos do acervo", () => {
    const convencao = classifica(
      "Documentos do Condomínio/Breeze-Bosque-da-Saude-Convencao-de-Condominio-registrada.pdf",
    );
    expect(convencao.tipo).toBe("convencao");
    expect(convencao.visibilidade).toBe("publico");

    const regimento = classifica(
      "Documentos do Condomínio/RI - Regulamento Interno - Breeze Bosque da Saúde.pdf",
    );
    expect(regimento.tipo).toBe("regimento");
    expect(regimento.visibilidade).toBe("publico");
  });

  it("fecha cotação de fornecedor no conselho", () => {
    // Proposta concorrente em aberto não é leitura de todo mundo — e continua
    // fechada depois da decisão.
    const r = classifica("Documentos do Condomínio/Orçamentos Segurança/GPA Engenharia.pdf");
    expect(r.tipo).toBe("documentacao_obra");
    expect(r.visibilidade).toBe("conselho");
  });

  it("extrai competência de balancete", () => {
    const r = classifica("Documentos do Condomínio/Prestação de Contas/PrestContas janeiro 2026.pdf");
    expect(r.tipo).toBe("balancete");
    expect(r.competencia).toBe("2026-01-01");
  });

  it("reconhece comunicado de governança pelo evento, não pela pasta", () => {
    expect(
      classifica("Documentos do Condomínio/Comunicados /2215 - CARTA DE RENÚNCIA - SINDICO [NOME].pdf")
        .tipo,
    ).toBe("comunicado_governanca");
    expect(
      classifica("Documentos do Condomínio/Comunicados /CARTA DE APRESENTAÇÃO BREEZE - [NOMES].pdf")
        .tipo,
    ).toBe("comunicado_governanca");
  });

  it("manda o que não reconhece para a conferência, em vez de chutar", () => {
    const r = classifica("Documentos do Condomínio/arquivo-sem-padrao-nenhum.pdf");
    expect(r.tipo).toBe("outros");
    expect(r.motivo).toMatch(/classifique na conferência/);
  });

  it("classifica os demais tipos do acervo real", () => {
    const casos: [string, string][] = [
      ["Documentos do Condomínio/AVCB-BREEZE-BOSQUE-SAUDE.pdf", "laudo_tecnico"],
      ["Documentos do Condomínio/Habite-se-Breeze-Bosque-Saude.pdf", "documento_construtora"],
      ["Documentos do Condomínio/MANUAL DO PROPRIETÁRIO.pdf", "documento_construtora"],
      [
        "Documentos do Condomínio/Previsão Orçamentária - Até 3 meses - dez-2025.pdf",
        "previsao_orcamentaria",
      ],
      [
        "Documentos do Condomínio/Comunicados /2215 COMPOSIÇÃO DA COTA MARÇO 2026.pdf",
        "demonstrativo_cota",
      ],
      [
        "Documentos do Condomínio/Apresentação Reunião Geral - 12.03.2026.pdf",
        "material_apoio_assembleia",
      ],
      [
        "Documentos do Condomínio/Comunicados /Utilizacao Elevadores.pdf",
        "comunicado",
      ],
    ];
    for (const [caminho, tipo] of casos) {
      expect(classifica(caminho).tipo, caminho).toBe(tipo);
    }
  });
});

describe("tituloDoNome", () => {
  it("tira o código da administradora e o sufixo de site", () => {
    expect(tituloDoNome("22115 - BREEZE AGE 04.02.2026 site.pdf")).toBe(
      "BREEZE AGE 04.02.2026",
    );
  });

  it("tira o sufixo de cópia", () => {
    expect(
      tituloDoNome("2215 - LEMBRETE –  ASSEMBLEIA GERAL EXTRAORDINÁRIA – 04.02.2026 (1).pdf"),
    ).toBe("LEMBRETE – ASSEMBLEIA GERAL EXTRAORDINÁRIA – 04.02.2026");
  });
});

describe("dataDoNome", () => {
  it("entende os separadores que o acervo usa", () => {
    expect(dataDoNome("AGE 04.02.2026")).toBe("2026-02-04");
    expect(dataDoNome("reuniao 12_03_26")).toBe("2026-03-12");
  });

  it("não inventa data", () => {
    expect(dataDoNome("Utilizacao Elevadores")).toBeNull();
  });
});

describe("competenciaDoNome", () => {
  it("entende mês por extenso e abreviado", () => {
    expect(competenciaDoNome("PrestContas dezembro 2025")).toBe("2025-12-01");
    expect(competenciaDoNome("Previsão Orçamentária - Até 3 meses - dez-2025")).toBe(
      "2025-12-01",
    );
  });
});
