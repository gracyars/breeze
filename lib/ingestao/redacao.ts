import { cpfValido, normalizaCpf } from "@/lib/identidade/cpf";

/**
 * Redação de identificador pessoal no texto extraído, antes de ele ser gravado.
 *
 * **Por que existe, e por que não é opcional.** O acervo real tem CPF em claro em
 * dois documentos: a ata da AGI de 04.12.2025 (CPF e RG do síndico) e — pior — a
 * página 18 da **Convenção**, que é o único documento de visibilidade *pública*
 * do condomínio. Sem redação, publicar a Convenção transforma "qual o CPF do
 * síndico" numa consulta de busca que **o anônimo** responde. O documento tem de
 * ser público por decisão (Briefing §7.1); o CPF de ninguém tem.
 *
 * **O que é redigido e o que não é.** Redige-se o texto **extraído** — o que vai
 * para `documento_paginas.texto`, para `texto_nativo` e, por consequência, para
 * os `chunks` e para a busca. O **PDF original não é tocado**: ele continua
 * íntegro no Storage, atrás de URL assinada de vida curta e da mesma RLS de
 * sempre. Isso preserva as duas coisas ao mesmo tempo — a prova documental, que
 * é metade do produto, e a minimização (LGPD art. 6º, III), que é o que impede o
 * documento de virar um índice de CPF pesquisável.
 *
 * **CPF sem formatação só é redigido se os dígitos verificadores fecharem.**
 * Onze dígitos seguidos aparecem em número de processo, protocolo e matrícula;
 * mascarar todos eles destruiria dado legítimo de balancete e de habite-se. A
 * validação é a diferença entre redigir e mutilar.
 */

export interface Redacao {
  texto: string;
  /** Quantos identificadores foram mascarados, por espécie. */
  ocorrencias: { cpf: number; rg: number };
}

const CPF_FORMATADO = /\b\d{3}\.\d{3}\.\d{3}-\d{2}\b/g;
const CPF_SOLTO = /\b\d{11}\b/g;
/** RG paulista: `12.345.678-9` ou `12.345.678-X`. */
const RG_FORMATADO = /\b\d{1,2}\.\d{3}\.\d{3}-[0-9Xx]\b/g;

export const MASCARA_CPF = "***.***.***-**";
export const MASCARA_RG = "**.***.***-*";

export function redigeDadosPessoais(texto: string): Redacao {
  let cpf = 0;
  let rg = 0;

  let saida = texto.replace(CPF_FORMATADO, () => {
    // Formatado é inequívoco: ninguém escreve número de processo assim.
    cpf += 1;
    return MASCARA_CPF;
  });

  saida = saida.replace(CPF_SOLTO, (achado) => {
    if (!cpfValido(normalizaCpf(achado))) return achado;
    cpf += 1;
    return MASCARA_CPF;
  });

  saida = saida.replace(RG_FORMATADO, () => {
    rg += 1;
    return MASCARA_RG;
  });

  return { texto: saida, ocorrencias: { cpf, rg } };
}

/** Há identificador pessoal em claro neste texto? Só conta, não altera. */
export function contaIdentificadores(texto: string): { cpf: number; rg: number } {
  return redigeDadosPessoais(texto).ocorrencias;
}
