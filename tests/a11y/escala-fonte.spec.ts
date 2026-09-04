import { expect, test } from "@playwright/test";

/**
 * Escala de fonte e refluxo (SPEC §6.5, WCAG 1.4.4 e 1.4.10).
 *
 * O morador idoso costuma já ter a fonte do navegador aumentada. Se algum
 * agente usar `px` em tamanho de texto ou altura fixa em container de texto,
 * este teste quebra: com a raiz em 200%, tudo tem que crescer junto e nada
 * pode gerar rolagem horizontal na página.
 */

const LARGURA_MINIMA = 320; // piso de 1.4.10

async function temRolagemHorizontal(page: import("@playwright/test").Page) {
  return page.evaluate(() => {
    const el = document.documentElement;
    return el.scrollWidth - el.clientWidth > 1;
  });
}

test("corpo padrão tem no mínimo 18px na escala normal", async ({ page }) => {
  await page.goto("/design-system");
  const tamanho = await page.evaluate(() =>
    Number.parseFloat(getComputedStyle(document.body).fontSize),
  );
  expect(tamanho).toBeGreaterThanOrEqual(18);
});

test("nenhum texto do sistema fica abaixo de 16px", async ({ page }) => {
  await page.goto("/design-system");
  const menores = await page.evaluate(() => {
    const fora: string[] = [];
    for (const el of document.querySelectorAll("main *")) {
      if (!el.textContent?.trim()) continue;
      if (el.children.length > 0) continue; // só folhas de texto
      const tamanho = Number.parseFloat(getComputedStyle(el).fontSize);
      if (tamanho < 16) fora.push(`${el.tagName}: ${tamanho}px`);
    }
    return fora;
  });
  expect(menores).toEqual([]);
});

test("a 200% de fonte, tudo escala e não há rolagem horizontal", async ({
  page,
}) => {
  await page.setViewportSize({ width: LARGURA_MINIMA, height: 720 });
  await page.goto("/design-system");

  // Equivale a "fonte muito grande" nas preferências do navegador. Só funciona
  // se toda a escala tipográfica estiver em rem — que é a regra do sistema.
  await page.addStyleTag({ content: "html { font-size: 200% !important; }" });
  await page.waitForTimeout(150);

  const tamanhoCorpo = await page.evaluate(() =>
    Number.parseFloat(getComputedStyle(document.body).fontSize),
  );
  expect(tamanhoCorpo).toBeGreaterThanOrEqual(35); // 18px * 2

  expect(await temRolagemHorizontal(page)).toBe(false);

  // Conteúdo essencial continua visível e legível, não cortado.
  await expect(page.getByRole("heading", { level: 1 })).toBeVisible();
  await expect(page.getByTestId("texto-legal")).toBeVisible();
});

test("refluxo em 320px sem zoom", async ({ page }) => {
  await page.setViewportSize({ width: LARGURA_MINIMA, height: 720 });
  await page.goto("/design-system");
  expect(await temRolagemHorizontal(page)).toBe(false);
});
