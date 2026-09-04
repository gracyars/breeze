import { readFileSync } from "node:fs";
import path from "node:path";
import { describe, expect, it } from "vitest";

/**
 * Contrato de contraste dos tokens (SPEC §6.5).
 *
 * Isto trava a paleta: qualquer agente que mexer num `--color-*` de
 * app/globals.css e derrubar o contraste quebra o CI aqui, antes de virar
 * problema para um morador idoso. O teste de contraste renderizado
 * (tests/a11y/contraste.spec.ts, axe) cobre a composição; este cobre o token.
 */

const CSS = readFileSync(
  path.resolve(import.meta.dirname, "../../app/globals.css"),
  "utf8",
);

function tokens(): Record<string, string> {
  const mapa: Record<string, string> = {};
  for (const [, nome, hex] of CSS.matchAll(
    /--color-([a-z0-9-]+):\s*(#[0-9a-fA-F]{6})/g,
  )) {
    mapa[nome] = hex.toLowerCase();
  }
  return mapa;
}

function canal(v: number): number {
  const c = v / 255;
  return c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4;
}

function luminancia(hex: string): number {
  const n = Number.parseInt(hex.slice(1), 16);
  const r = canal((n >> 16) & 255);
  const g = canal((n >> 8) & 255);
  const b = canal(n & 255);
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

function contraste(a: string, b: string): number {
  const la = luminancia(a);
  const lb = luminancia(b);
  const [claro, escuro] = la > lb ? [la, lb] : [lb, la];
  return (claro + 0.05) / (escuro + 0.05);
}

const T = tokens();

/** [frente, fundo, mínimo exigido, motivo] */
const PARES: [string, string, number, string][] = [
  // Texto AA/AAA sobre as superfícies neutras.
  ["tinta", "papel", 7, "texto principal — AAA"],
  ["tinta", "superficie", 7, "texto principal em card — AAA"],
  ["tinta", "superficie-alt", 7, "texto em linha zebrada — AAA"],
  ["tinta-suave", "papel", 7, "texto secundário — AAA"],
  ["tinta-suave", "superficie-muda", 4.5, "texto desabilitado legível — AA"],
  ["tinta-fraca", "papel", 4.5, "meta e placeholder — AA"],

  // Ação: um único azul profundo.
  ["acao", "papel", 4.5, "link e texto de ação — AA"],
  ["acao", "superficie", 4.5, "ação sobre card — AA"],
  ["acao", "acao-suave", 4.5, "ação sobre realce — AA"],

  // Status financeiro: SEMPRE AAA, é texto financeiro (§6.5).
  ["positivo", "papel", 7, "status positivo — AAA"],
  ["positivo", "positivo-suave", 7, "badge positivo — AAA"],
  ["negativo", "papel", 7, "status negativo — AAA"],
  ["negativo", "negativo-suave", 7, "badge negativo — AAA"],
  ["atencao", "papel", 7, "severidade de alerta — AAA"],
  ["atencao", "atencao-suave", 7, "badge de alerta — AAA"],

  // Erro de formulário: vermelho semântico, mesmo rigor.
  ["erro", "papel", 7, "mensagem de erro — AAA"],
  ["erro", "superficie", 7, "mensagem de erro em card — AAA"],
  ["erro", "erro-suave", 7, "erro sobre realce — AAA"],
  ["erro", "superficie-muda", 4.5, "erro em bloco secundário — AA"],

  // Limites e elementos gráficos: WCAG 1.4.11 exige 3:1.
  ["borda-forte", "papel", 3, "borda de campo e tabela — 1.4.11"],
  ["borda-forte", "superficie", 3, "borda de campo sobre branco — 1.4.11"],
  ["grafico-contorno", "papel", 3, "contorno de barra clara — 1.4.11"],
  ["foco", "papel", 3, "anel de foco — 1.4.11"],
];

describe("contraste dos tokens de cor", () => {
  it("define todos os tokens usados nos pares", () => {
    for (const [frente, fundo] of PARES) {
      expect(T[frente], `--color-${frente} ausente`).toBeDefined();
      expect(T[fundo], `--color-${fundo} ausente`).toBeDefined();
    }
  });

  it.each(PARES)(
    "%s sobre %s ≥ %s:1 (%s)",
    (frente, fundo, minimo) => {
      const razao = contraste(T[frente], T[fundo]);
      expect(
        Number(razao.toFixed(2)),
        `${frente}/${fundo} = ${razao.toFixed(2)}:1`,
      ).toBeGreaterThanOrEqual(minimo);
    },
  );

  it("texto branco sobre o azul de ação é AAA (botão primário)", () => {
    expect(contraste("#ffffff", T.acao)).toBeGreaterThanOrEqual(7);
    expect(contraste("#ffffff", T["acao-forte"])).toBeGreaterThanOrEqual(7);
  });

  it("erro e negativo compartilham o mesmo vermelho", () => {
    // Um vermelho só no produto. Se alguém divergir os dois tokens, que seja
    // por decisão consciente — este teste é o pedágio.
    expect(T.erro).toBe(T.negativo);
    expect(T["erro-suave"]).toBe(T["negativo-suave"]);
  });

  it("verde e vermelho NÃO se distinguem entre si — por isso o texto é obrigatório", () => {
    // Deuteranopia funde os dois matizes e a luminância deles é próxima de
    // propósito (ambos escuros, ambos AAA). Consequência de projeto, registrada
    // aqui: status financeiro nunca pode ser comunicado só por cor — o
    // BadgeStatus exige `children` textual.
    expect(contraste(T.positivo, T.negativo)).toBeLessThan(2);
    expect(luminancia(T.positivo)).toBeLessThan(0.2);
    expect(luminancia(T.negativo)).toBeLessThan(0.2);
  });
});
