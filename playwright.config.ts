import { defineConfig, devices } from "@playwright/test";

/**
 * Dois usos, separados de propósito em projetos distintos:
 *
 * - **a11y** (F0): contraste, escala de fonte e alvo de toque sobre
 *   /design-system. Roda em qualquer lugar, não depende de banco.
 * - **e2e** (F1, corte C1): o fluxo de entrada de verdade — magic link, sessão,
 *   segundo fator. **Depende do stack Supabase local de pé** (`supabase start`)
 *   e por isso não entra no mesmo comando: `pnpm test:a11y` segue sendo o que o
 *   CI chama hoje, e `pnpm test:e2e` é o novo. Wire-up do e2e no CI é do
 *   `devops` — está registrado como dívida.
 */
export default defineConfig({
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 1 : 0,
  reporter: process.env.CI ? "github" : "list",
  use: {
    baseURL: process.env.BASE_URL ?? "http://127.0.0.1:3000",
    trace: "on-first-retry",
  },
  projects: [
    {
      name: "chromium",
      testDir: "./tests/a11y",
      use: { ...devices["Desktop Chrome"] },
    },
    {
      // O morador usa celular (briefing §3). O piso de 320px vale aqui.
      name: "celular",
      testDir: "./tests/a11y",
      use: { ...devices["Pixel 5"] },
    },
    {
      name: "e2e",
      testDir: "./tests/e2e",
      use: { ...devices["Desktop Chrome"] },
    },
  ],
  webServer: {
    command: "pnpm dev",
    url: "http://127.0.0.1:3000/design-system",
    reuseExistingServer: !process.env.CI,
    timeout: 120_000,
  },
});
