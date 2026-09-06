/**
 * Substituto de `server-only` para o Vitest.
 *
 * O pacote real quebra de propósito quando importado fora de um Server
 * Component — é essa quebra que impede a chave `service_role` de vazar para o
 * navegador por engano. No teste unitário não existe fronteira servidor/cliente,
 * então o import resolve para este arquivo vazio.
 *
 * A garantia continua valendo onde importa: `next build` usa o pacote real.
 */
export {};
