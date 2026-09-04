import AxeBuilder from "@axe-core/playwright";
import { expect, test } from "@playwright/test";

/**
 * Contraste renderizado (SPEC §6.5).
 * AA em toda a página; AAA (`color-contrast-enhanced`) obrigatório em texto
 * financeiro: valor monetário, célula numérica e badge de status.
 *
 * O contraste dos tokens isolados é travado em tests/unit/contraste-tokens.test.ts.
 * Este teste pega o que só aparece na composição: texto sobre tinte, sobre
 * linha zebrada, dentro de badge.
 */

test.beforeEach(async ({ page }) => {
  await page.goto("/design-system");
  await page.waitForLoadState("networkidle");
});

test("a página inteira passa em contraste AA", async ({ page }) => {
  const resultado = await new AxeBuilder({ page })
    .withRules(["color-contrast"])
    .analyze();

  expect(
    resultado.violations.map((v) => ({
      id: v.id,
      alvos: v.nodes.map((n) => n.target.join(" ")),
    })),
  ).toEqual([]);
});

test("texto financeiro passa em contraste AAA", async ({ page }) => {
  const resultado = await new AxeBuilder({ page })
    .include('[data-slot="badge-status"]')
    .include('[data-slot="table-cell"]')
    .include('[data-slot="table-footer"]')
    .include(".numero")
    .withRules(["color-contrast-enhanced"])
    .analyze();

  expect(
    resultado.violations.map((v) => ({
      id: v.id,
      alvos: v.nodes.map((n) => n.target.join(" ")),
    })),
  ).toEqual([]);
});

test("nenhum status financeiro depende só de cor", async ({ page }) => {
  const badges = page.locator('[data-slot="badge-status"]');
  const total = await badges.count();
  expect(total).toBeGreaterThan(0);

  for (let i = 0; i < total; i++) {
    const texto = (await badges.nth(i).innerText()).trim();
    // Fora o glifo redundante, tem que sobrar palavra.
    expect(texto.replace(/[▲▼!•\s]/g, "").length).toBeGreaterThan(2);
  }
});
