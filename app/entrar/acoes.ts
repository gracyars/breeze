"use server";

import { headers } from "next/headers";

import { consome } from "@/lib/auth/limitador";
import { cpfValido, hashDeCpf, normalizaCpf, paraBytea } from "@/lib/identidade/cpf";
import { clienteDoServidor } from "@/lib/supabase/servidor";
import { clienteDeServico } from "@/lib/supabase/servico";

/**
 * Início de sessão: CPF **ou** e-mail → magic link para o e-mail cadastrado.
 *
 * A regra que governa este arquivo inteiro (ADR-0003, regra 2): **a resposta é
 * sempre a mesma.** CPF que existe, CPF que não existe, CPF mal digitado,
 * e-mail de outra pessoa, pessoa sem e-mail cadastrado, limite de tentativas
 * estourado — tudo devolve a mesma frase. Qualquer diferença transforma a tela
 * de login num oráculo de "esta pessoa mora aqui", que é vazamento de dado
 * pessoal antes mesmo de alguém entrar.
 *
 * O mesmo vale para o tempo: o HMAC e o lookup rodam **sempre**, inclusive
 * quando já se sabe que não vai dar em nada. Responder rápido para o CPF
 * inexistente contaria a mesma história que a mensagem contaria.
 */

export interface EstadoDeEntrada {
  enviado: boolean;
  mensagem: string;
}

/** A única resposta que esta ação dá. Não existe variante. */
const RESPOSTA_UNICA =
  "Se houver cadastro com esse CPF ou e-mail, enviamos um link de acesso. Confira sua caixa de entrada e o spam.";

export async function iniciarEntrada(
  _estadoAnterior: EstadoDeEntrada,
  formulario: FormData,
): Promise<EstadoDeEntrada> {
  const identificador = String(formulario.get("identificador") ?? "").trim();
  const cabecalhos = await headers();
  const ip =
    cabecalhos.get("x-forwarded-for")?.split(",")[0]?.trim() ?? "desconhecido";

  // Limite por IP e por identificador (ADR-0003, regra 3). Estourar não muda a
  // resposta — só deixa de fazer o trabalho.
  const dentroDoLimite =
    consome(`ip:${ip}`, { maximo: 20, janelaSegundos: 3600 }) &&
    consome(`id:${identificador.toLowerCase()}`, { maximo: 5, janelaSegundos: 3600 });

  const email = await resolveEmail(identificador);

  if (email && dentroDoLimite) {
    const supabase = await clienteDoServidor();
    await supabase.auth.signInWithOtp({
      email,
      options: {
        // Ninguém entra por digitar um e-mail: a conta precisa existir, e quem
        // cadastra pessoa é a editora (ADR-0003, regra 4).
        shouldCreateUser: false,
        emailRedirectTo: `${origemDaAplicacao(cabecalhos.get("origin"))}/auth/confirmar`,
      },
    });
  }

  return { enviado: true, mensagem: RESPOSTA_UNICA };
}

/**
 * Descobre para qual e-mail mandar o link — ou `null`.
 *
 * O lookup usa `service_role` porque **acontece antes de existir sessão**: não há
 * como ser `authenticated` aqui. É o uso previsto em V4 da auditoria de F0, e o
 * `grant select on public.pessoas to service_role` existe exatamente para ele.
 */
async function resolveEmail(identificador: string): Promise<string | null> {
  const supabase = clienteDeServico();

  if (identificador.includes("@")) {
    const email = identificador.toLowerCase();
    const { data } = await supabase
      .from("pessoas")
      .select("email, ativa")
      .eq("email", email)
      .maybeSingle();
    return data?.ativa ? (data.email ?? null) : null;
  }

  // Trabalho constante: o HMAC roda mesmo para CPF mal digitado, e o lookup roda
  // mesmo sabendo que não vai casar. É o que iguala o tempo de resposta.
  const cpf = normalizaCpf(identificador);
  const hash = hashDeCpf(cpf.length === 11 ? cpf : cpf.padStart(11, "0"));
  const { data } = await supabase
    .from("pessoas")
    .select("email, ativa")
    .eq("cpf_hash", paraBytea(hash))
    .maybeSingle();

  if (!cpfValido(cpf)) return null;
  // Pessoa inativa não entra: o acesso cessa no fim do vínculo, sem carência
  // (veto do `juridico-lgpd`, `vinculos.fim` + 0 dias).
  return data?.ativa ? (data.email ?? null) : null;
}

function origemDaAplicacao(origem: string | null): string {
  return origem ?? process.env.NEXT_PUBLIC_SITE_URL ?? "http://127.0.0.1:3000";
}
