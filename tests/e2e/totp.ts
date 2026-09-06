import { createHmac } from "node:crypto";

/**
 * TOTP (RFC 6238) para o teste fazer o papel do app autenticador.
 *
 * Vive só no teste: o Breeze **nunca** gera código TOTP — ele verifica o que a
 * pessoa digita, e quem gera é o celular dela. Há uma cópia disto em
 * `scripts/probe/aal2-gotrue.ts` de propósito: aquela sonda precisa rodar
 * sozinha, sem depender da árvore de testes.
 */
const ALFABETO_BASE32 = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";

function base32ParaBytes(segredo: string): Buffer {
  let bits = "";
  for (const caractere of segredo.toUpperCase().replace(/=+$/, "")) {
    const indice = ALFABETO_BASE32.indexOf(caractere);
    if (indice === -1) continue;
    bits += indice.toString(2).padStart(5, "0");
  }
  const bytes: number[] = [];
  for (let i = 0; i + 8 <= bits.length; i += 8) {
    bytes.push(Number.parseInt(bits.slice(i, i + 8), 2));
  }
  return Buffer.from(bytes);
}

export function codigoTotp(segredo: string, emSegundos = Date.now() / 1000): string {
  const contador = Math.floor(emSegundos / 30);
  const buffer = Buffer.alloc(8);
  buffer.writeBigUInt64BE(BigInt(contador));
  const hmac = createHmac("sha1", base32ParaBytes(segredo)).update(buffer).digest();
  const deslocamento = hmac[hmac.length - 1] & 0x0f;
  const binario =
    ((hmac[deslocamento] & 0x7f) << 24) |
    ((hmac[deslocamento + 1] & 0xff) << 16) |
    ((hmac[deslocamento + 2] & 0xff) << 8) |
    (hmac[deslocamento + 3] & 0xff);
  return String(binario % 1_000_000).padStart(6, "0");
}
