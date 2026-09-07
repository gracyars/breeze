import { describe, expect, it } from "vitest";

import {
  contaIdentificadores,
  MASCARA_CPF,
  redigeDadosPessoais,
} from "@/lib/ingestao/redacao";

/**
 * Os dois casos que motivam o módulo são reais e estavam no banco: a ata da AGI
 * de 04.12.2025 e a **página 18 da Convenção** — o único documento público do
 * condomínio. Os CPFs abaixo são sintéticos, com verificadores calculados para o
 * teste; os reais não entram no repositório.
 */
describe("redigeDadosPessoais", () => {
  it("mascara CPF formatado", () => {
    const { texto, ocorrencias } = redigeDadosPessoais(
      "Presente o Sr. Fulano, inscrito no CPF sob nº 529.982.247-25, residente na unidade 101.",
    );
    expect(texto).toContain(MASCARA_CPF);
    expect(texto).not.toContain("529.982.247-25");
    expect(ocorrencias.cpf).toBe(1);
    // O resto da frase fica intacto: a prova documental é metade do produto.
    expect(texto).toContain("residente na unidade 101");
  });

  it("mascara CPF sem formatação SÓ quando os verificadores fecham", () => {
    const { texto, ocorrencias } = redigeDadosPessoais(
      "CPF 52998224725 e processo nº 58709252026 e protocolo 12345678901",
    );
    expect(texto).toContain(MASCARA_CPF);
    // Onze dígitos que não são CPF continuam onde estavam — número de processo,
    // protocolo e matrícula aparecem no acervo e são dado legítimo.
    expect(texto).toContain("58709252026");
    expect(texto).toContain("12345678901");
    expect(ocorrencias.cpf).toBe(1);
  });

  it("mascara RG no formato que a ata usa", () => {
    const { texto, ocorrencias } = redigeDadosPessoais("portador do RG 12.345.678-9");
    expect(texto).not.toContain("12.345.678-9");
    expect(ocorrencias.rg).toBe(1);
  });

  it("não confunde valor monetário com identificador", () => {
    // Balancete é coluna de número; mascarar valor destruiria o produto.
    const texto = "Taxa de administração 1.234,56 e fundo de reserva 12.345,67";
    expect(redigeDadosPessoais(texto).texto).toBe(texto);
  });

  it("não toca em data, artigo nem fração ideal", () => {
    const texto =
      "Artigo 5º - A fração ideal de 1,9389% na assembleia de 04.02.2026, conforme art. 1.348.";
    expect(redigeDadosPessoais(texto).texto).toBe(texto);
  });

  it("conta sem alterar", () => {
    const contagem = contaIdentificadores("CPF 529.982.247-25 e RG 12.345.678-9");
    expect(contagem).toEqual({ cpf: 1, rg: 1 });
  });

  it("é idempotente — redigir o já redigido não muda nada", () => {
    // Importa porque o reprocessamento é comando corriqueiro (SPEC §3): a
    // segunda passada não pode contar de novo nem corromper a máscara.
    const uma = redigeDadosPessoais("CPF 529.982.247-25");
    const duas = redigeDadosPessoais(uma.texto);
    expect(duas.texto).toBe(uma.texto);
    expect(duas.ocorrencias.cpf).toBe(0);
  });
});
