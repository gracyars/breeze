"use server";

import { revalidatePath } from "next/cache";

import { bancoDireto } from "@/lib/db";
import type { Database } from "@/lib/supabase/database.types";
import { clienteDoServidor } from "@/lib/supabase/servidor";

/**
 * As duas decisões que só uma pessoa toma: publicar e reprocessar.
 *
 * Publicar é o ato que o SPEC §3.5 exige que seja humano — o pipeline para em
 * `em_revisao` de propósito e nada aqui automatiza a passagem. A autorização,
 * como sempre, é do banco: a policy de `UPDATE` em `documentos` exige
 * `app.eh_editor()`, que só reconhece editor com `aal2`.
 */

type Visibilidade = Database["public"]["Enums"]["visibilidade_documento"];

const VISIBILIDADES: readonly Visibilidade[] = [
  "publico",
  "autenticado",
  "conselho",
  "restrito",
] as const;

/**
 * Valor do formulário vira valor do enum, ou cai no mais fechado.
 *
 * O padrão em caso de dúvida é `conselho`, não `publico`: campo adulterado tem
 * de fechar acesso, nunca abrir. A RLS não seria enganada de qualquer forma —
 * ela lê a coluna, não o formulário —, mas gravar visibilidade errada publica
 * conteúdo errado, e isso a RLS obedece.
 */
function comoVisibilidade(valor: FormDataEntryValue | null): Visibilidade {
  const texto = String(valor ?? "");
  return (VISIBILIDADES as readonly string[]).includes(texto)
    ? (texto as Visibilidade)
    : "conselho";
}

export interface ResultadoDaCuradoria {
  ok: boolean;
  mensagem?: string;
}

export async function publicar(
  _anterior: ResultadoDaCuradoria,
  formulario: FormData,
): Promise<ResultadoDaCuradoria> {
  const documentoId = String(formulario.get("documento_id") ?? "");
  const visibilidade = comoVisibilidade(formulario.get("visibilidade"));

  const supabase = await clienteDoServidor();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return { ok: false, mensagem: "Sessão expirada. Entre de novo." };

  // `publicado_por` é a pessoa, não o usuário de autenticação: é o registro de
  // quem assinou a publicação, e o schema exige que exista junto com a data.
  const { data: pessoa } = await supabase
    .from("pessoas")
    .select("id")
    .eq("auth_user_id", user.id)
    .maybeSingle();

  if (!pessoa) {
    return { ok: false, mensagem: "Sua conta não está ligada a uma pessoa do cadastro." };
  }

  const { error } = await supabase
    .from("documentos")
    .update({
      status: "publicado",
      visibilidade,
      publicado_em: new Date().toISOString(),
      publicado_por: pessoa.id,
    })
    .eq("id", documentoId);

  if (error) {
    return {
      ok: false,
      mensagem:
        "O banco recusou a publicação. Confirme o segundo fator desta sessão — publicar exige ele.",
    };
  }

  revalidatePath("/curadoria");
  revalidatePath("/acervo");
  return { ok: true };
}

/**
 * Devolve à fila um documento que falhou.
 *
 * Passa por `job.enfileirar` como todo mundo (ADR-0025 §2): `insert` direto em
 * `job.fila` não existe em lugar nenhum, e é a função que aplica a chave de
 * idempotência — sem ela, clicar duas vezes viraria dois jobs.
 */
export async function reenfileirar(
  _anterior: ResultadoDaCuradoria,
  formulario: FormData,
): Promise<ResultadoDaCuradoria> {
  const documentoId = String(formulario.get("documento_id") ?? "");

  const supabase = await clienteDoServidor();
  const { data } = await supabase
    .from("documentos")
    .select("id, versao_pipeline")
    .eq("id", documentoId)
    .maybeSingle();

  if (!data) return { ok: false, mensagem: "Documento não encontrado." };

  const { error } = await supabase
    .from("documentos")
    .update({ status: "pendente", erro_detalhe: null })
    .eq("id", documentoId);

  if (error) {
    return { ok: false, mensagem: "Não consegui devolver o documento à fila." };
  }

  await bancoDireto().query(
    `select job.enfileirar('hash_dedupe', $1::uuid, $2, '{}'::jsonb, 100)`,
    [documentoId, `hash_dedupe:${documentoId}:v${data.versao_pipeline}:retry-${Date.now()}`],
  );

  revalidatePath("/curadoria");
  return { ok: true, mensagem: "Devolvido à fila. Rode o worker para reprocessar." };
}
