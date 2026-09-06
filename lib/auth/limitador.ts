import "server-only";

/**
 * Limitador de tentativas de início de login (ADR-0003, regra 3).
 *
 * Janela deslizante em memória do processo. **Limite conhecido e assumido:** com
 * mais de uma instância servindo, cada uma conta a sua parte, e o teto efetivo
 * multiplica pelo número de instâncias. Hoje o Breeze roda numa instância só; no
 * dia em que não rodar, isto precisa de contador compartilhado (tabela no
 * Postgres serve — não há Redis no projeto e não vai haver por causa disto).
 *
 * Está aqui como **segunda** camada: o Supabase Auth também limita envio de
 * e-mail. A camada da aplicação existe porque o limite do Auth é por e-mail
 * enviado, e o ataque que interessa barrar — varrer CPF para descobrir quem mora
 * no prédio — nem chega a enviar e-mail.
 */

interface Janela {
  contagem: number;
  expiraEm: number;
}

const janelas = new Map<string, Janela>();

export interface Limite {
  /** Tentativas permitidas dentro da janela. */
  maximo: number;
  /** Tamanho da janela, em segundos. */
  janelaSegundos: number;
}

/**
 * Consome uma tentativa. `true` = pode seguir.
 *
 * Quem chama **não deve** contar isto ao usuário de forma diferente do caminho
 * normal: dizer "muitas tentativas para este CPF" confirma que o CPF existe.
 */
export function consome(chave: string, limite: Limite, agora = Date.now()): boolean {
  const janela = janelas.get(chave);

  if (!janela || janela.expiraEm <= agora) {
    janelas.set(chave, { contagem: 1, expiraEm: agora + limite.janelaSegundos * 1000 });
    limpaVencidas(agora);
    return true;
  }

  if (janela.contagem >= limite.maximo) return false;

  janela.contagem += 1;
  return true;
}

/** Varredura preguiçosa: o mapa não cresce sem limite em processo longevo. */
function limpaVencidas(agora: number): void {
  if (janelas.size < 1000) return;
  for (const [chave, janela] of janelas) {
    if (janela.expiraEm <= agora) janelas.delete(chave);
  }
}

/** Só para teste — zera o estado entre casos. */
export function reiniciaLimitador(): void {
  janelas.clear();
}
