import { beforeEach, describe, expect, it } from "vitest";

import {
  cpfValido,
  digitosParaExibicao,
  hashDeCpf,
  hashesIguais,
  normalizaCpf,
  paraBytea,
} from "@/lib/identidade/cpf";

/**
 * CPFs usados aqui são **sintéticos**: dígitos verificadores calculados para o
 * teste, não pertencem a ninguém. Testar identificador de pessoa real dentro do
 * repositório seria vazar dado pessoal para o git para sempre.
 */
const CPF_SINTETICO = "52998224725";

describe("normalizaCpf", () => {
  it("descarta pontuação", () => {
    expect(normalizaCpf("529.982.247-25")).toBe(CPF_SINTETICO);
  });
});

describe("cpfValido", () => {
  it("aceita CPF com verificadores corretos", () => {
    expect(cpfValido(CPF_SINTETICO)).toBe(true);
    expect(cpfValido("529.982.247-25")).toBe(true);
  });

  it("recusa verificador errado", () => {
    expect(cpfValido("52998224724")).toBe(false);
  });

  it("recusa sequência repetida, que passa na conta e não existe", () => {
    expect(cpfValido("11111111111")).toBe(false);
    expect(cpfValido("00000000000")).toBe(false);
  });

  it("recusa tamanho errado", () => {
    expect(cpfValido("5299822472")).toBe(false);
    expect(cpfValido("")).toBe(false);
  });
});

describe("hashDeCpf", () => {
  beforeEach(() => {
    process.env.CPF_HASH_PEPPER = "pepper-de-teste-nao-usar-em-lugar-nenhum";
  });

  it("é determinístico e independe de pontuação", () => {
    const a = hashDeCpf("529.982.247-25");
    const b = hashDeCpf(CPF_SINTETICO);
    expect(hashesIguais(a, b)).toBe(true);
    expect(a.length).toBe(32);
  });

  it("muda quando o pepper muda — é o que torna o hash inútil sem o segredo", () => {
    const comPepperA = hashDeCpf(CPF_SINTETICO);
    process.env.CPF_HASH_PEPPER = "outro-pepper";
    const comPepperB = hashDeCpf(CPF_SINTETICO);
    expect(hashesIguais(comPepperA, comPepperB)).toBe(false);
  });

  it("falha alto sem pepper, em vez de gravar hash com segredo vazio", () => {
    delete process.env.CPF_HASH_PEPPER;
    expect(() => hashDeCpf(CPF_SINTETICO)).toThrow(/CPF_HASH_PEPPER/);
  });

  it("serializa como bytea hexadecimal", () => {
    expect(paraBytea(Buffer.from([0xde, 0xad]))).toBe("\\xdead");
  });
});

describe("digitosParaExibicao", () => {
  it("devolve os dígitos 7–9 e nunca os verificadores", () => {
    // 529.982.247-25 → posições 7-9 são "247"; "25" (verificadores) fica de fora.
    expect(digitosParaExibicao(CPF_SINTETICO)).toBe("247");
    expect(digitosParaExibicao(CPF_SINTETICO)).not.toContain("25");
  });

  it("devolve nulo quando não há CPF completo", () => {
    expect(digitosParaExibicao("529982")).toBeNull();
  });
});
