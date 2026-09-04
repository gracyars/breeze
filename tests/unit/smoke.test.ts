import { describe, expect, it } from "vitest";

// Teste de fumaça para validar o pipeline (lint → typecheck → test → RLS → db push).
// Agentes de feature substituem/expandem isto; não remover sem colocar teste real no lugar.
describe("pipeline smoke test", () => {
  it("roda sob o Vitest configurado no CI", () => {
    expect(1 + 1).toBe(2);
  });
});
