import { beforeEach, describe, expect, it } from "vitest";

import { consome, reiniciaLimitador } from "@/lib/auth/limitador";

describe("limitador de tentativas de entrada", () => {
  beforeEach(() => {
    reiniciaLimitador();
  });

  it("libera até o máximo e barra a partir dele", () => {
    const limite = { maximo: 3, janelaSegundos: 60 };
    expect(consome("ip:1.2.3.4", limite, 1_000)).toBe(true);
    expect(consome("ip:1.2.3.4", limite, 1_100)).toBe(true);
    expect(consome("ip:1.2.3.4", limite, 1_200)).toBe(true);
    expect(consome("ip:1.2.3.4", limite, 1_300)).toBe(false);
  });

  it("conta cada chave separadamente", () => {
    const limite = { maximo: 1, janelaSegundos: 60 };
    expect(consome("ip:1.1.1.1", limite, 0)).toBe(true);
    expect(consome("ip:2.2.2.2", limite, 0)).toBe(true);
    expect(consome("ip:1.1.1.1", limite, 0)).toBe(false);
  });

  it("recomeça depois da janela", () => {
    const limite = { maximo: 1, janelaSegundos: 60 };
    expect(consome("id:fulano", limite, 0)).toBe(true);
    expect(consome("id:fulano", limite, 59_000)).toBe(false);
    expect(consome("id:fulano", limite, 60_001)).toBe(true);
  });
});
