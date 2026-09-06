import { createHmac, timingSafeEqual } from "node:crypto";

/**
 * CPF: normalização, validação e o HMAC que vira `pessoas.cpf_hash`.
 *
 * O CPF aqui **não é credencial** — é alias de identificação (ADR-0003). Ele não
 * concede sessão: só resolve qual e-mail recebe o magic link. Isso importa
 * porque CPF não é segredo e é enumerável; tratá-lo como senha seria entregar o
 * condomínio a quem tem uma lista de CPFs.
 *
 * O pepper vive **fora do banco**, em variável de ambiente (ADR-0014, SPEC §2.1).
 * Quem obtém um dump não obtém CPF nenhum: sem o pepper, `cpf_hash` é opaco.
 * Rotacionar o pepper é migração de dados sobre `pessoas` inteira.
 */

/** `123.456.789-09` → `12345678909`. Não valida nada; só tira o que não é dígito. */
export function normalizaCpf(entrada: string): string {
  return entrada.replace(/\D/g, "");
}

/**
 * Dígitos verificadores conferem?
 *
 * Serve para não gastar lookup com digitação errada e para a mensagem de erro do
 * formulário — **nunca** para decidir se responde diferente ao usuário. A tela
 * de login responde igual para CPF válido, inválido, cadastrado e inexistente
 * (ADR-0003, regra 2): a diferença viraria um oráculo de "esta pessoa mora aqui".
 */
export function cpfValido(entrada: string): boolean {
  const cpf = normalizaCpf(entrada);
  if (cpf.length !== 11) return false;
  // Sequências repetidas (11111111111) passam no algoritmo e não existem.
  if (/^(\d)\1{10}$/.test(cpf)) return false;

  for (const [tamanho, posicaoDoVerificador] of [
    [9, 9],
    [10, 10],
  ] as const) {
    let soma = 0;
    for (let i = 0; i < tamanho; i += 1) {
      soma += Number(cpf[i]) * (tamanho + 1 - i);
    }
    const resto = (soma * 10) % 11;
    const esperado = resto === 10 ? 0 : resto;
    if (esperado !== Number(cpf[posicaoDoVerificador])) return false;
  }
  return true;
}

/**
 * `HMAC-SHA256(cpf normalizado, pepper)` — os 32 bytes de `pessoas.cpf_hash`.
 *
 * Lança se o pepper não estiver configurado: subir sem ele produziria hash com
 * segredo vazio, isto é, um `cpf_hash` que qualquer um reproduz a partir de um
 * dump. Falhar alto na partida é melhor que gravar uma coluna inútil.
 */
export function hashDeCpf(entrada: string): Buffer {
  const pepper = process.env.CPF_HASH_PEPPER;
  if (!pepper) {
    throw new Error(
      "CPF_HASH_PEPPER não configurado — ver .env.example e ADR-0014 (o pepper vive fora do banco)",
    );
  }
  return createHmac("sha256", pepper).update(normalizaCpf(entrada), "utf8").digest();
}

/** Comparação de hash em tempo constante. */
export function hashesIguais(a: Buffer, b: Buffer): boolean {
  return a.length === b.length && timingSafeEqual(a, b);
}

/** Os dígitos 7–9, para exibição mascarada `***.***.789-**` (ADR-0014, regra 3). */
export function digitosParaExibicao(entrada: string): string | null {
  const cpf = normalizaCpf(entrada);
  // Nunca os verificadores: deles se deriva material que reduz a busca.
  return cpf.length === 11 ? cpf.slice(6, 9) : null;
}

/** `\x` + hex — formato que o PostgREST aceita para `bytea`. */
export function paraBytea(valor: Buffer): string {
  return `\\x${valor.toString("hex")}`;
}
