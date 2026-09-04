import { expect, test } from "@playwright/test";

/**
 * Alvo de toque ≥48px (SPEC §6.5 — mais rígido que o mínimo de 24px da WCAG
 * 2.5.8, de propósito: o público inclui pessoa idosa usando celular).
 *
 * Exceção legítima e única: link dentro de linha de texto corrido, que a
 * própria WCAG excepciona. Marque com `data-inline="true"` para sair daqui.
 */

const PISO = 48;

test("todo controle interativo tem pelo menos 48x48", async ({ page }) => {
  await page.goto("/design-system");

  const controles = page.locator(
    'main button, main a[href], main input, main select, main textarea, main [role="button"]',
  );
  const total = await controles.count();
  expect(total).toBeGreaterThan(0);

  const pequenos: string[] = [];
  for (let i = 0; i < total; i++) {
    const controle = controles.nth(i);
    if ((await controle.getAttribute("data-inline")) === "true") continue;
    if (!(await controle.isVisible())) continue;

    const caixa = await controle.boundingBox();
    if (!caixa) continue;

    if (caixa.height < PISO - 0.5 || caixa.width < PISO - 0.5) {
      const texto = (await controle.innerText()).trim().slice(0, 40);
      pequenos.push(
        `${await controle.evaluate((e) => e.tagName)} "${texto}" ${Math.round(
          caixa.width,
        )}x${Math.round(caixa.height)}`,
      );
    }
  }

  expect(pequenos).toEqual([]);
});
