import { defineConfig, devices } from "@playwright/test";

/**
 * Playwright é usado em F0 apenas para os testes de acessibilidade do design
 * system (contraste, escala de fonte e alvo de toque) sobre /design-system.
 * QA E2E de fluxo entra em F4 (SPEC §9) e pode ampliar `testDir`.
 */
export default defineConfig({
  testDir: "./tests/a11y",
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
      use: { ...devices["Desktop Chrome"] },
    },
    {
      // O morador usa celular (briefing §3). O piso de 320px vale aqui.
      name: "celular",
      use: { ...devices["Pixel 5"] },
    },
  ],
  webServer: {
    command: "pnpm dev",
    url: "http://127.0.0.1:3000/design-system",
    reuseExistingServer: !process.env.CI,
    timeout: 120_000,
  },
});
