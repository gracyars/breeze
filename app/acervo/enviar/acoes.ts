"use server";

import { randomUUID } from "node:crypto";

import { revalidatePath } from "next/cache";

import { bancoDireto } from "@/lib/db";
import { clienteDoServidor } from "@/lib/supabase/servidor";
import { clienteDeServico } from "@/lib/supabase/servico";

/**
 * Estágio 0 da ingestão: registrar o documento e pôr o pipeline para andar.
 *
 * A ordem é o desenho, não conveniência:
 *
 * 1. **O `insert` em `documentos` vai com a sessão da pessoa**, e a policy exige
 *    `app.eh_editor()` — que só reconhece editor com `aal2`. Quem recusa é o
 *    banco. Não há `if` de TypeScript nesta função decidindo quem pode publicar,
 *    e não deve haver: seria uma segunda fronteira de autorização (ADR-0012).
 * 2. **A URL assinada de upload é emitida depois**, com a chave de serviço.
 *    Assinar antes de a linha existir daria caminho de escrita no bucket a quem
 *    ainda não provou nada.
 * 3. **O enfileiramento acontece só quando o arquivo chegou** — o worker precisa
 *    do objeto para calcular o hash a partir do que realmente subiu (ADR-0004: o
 *    cliente pode mentir sobre o hash).
 */

export interface EnvioIniciado {
  ok: boolean;
  documentoId?: string;
  caminho?: string;
  urlDeUpload?: string;
  token?: string;
  mensagem?: string;
}

export async function iniciarEnvio(
  _anterior: EnvioIniciado,
  formulario: FormData,
): Promise<EnvioIniciado> {
  const titulo = String(formulario.get("titulo") ?? "").trim();
  const tipo = String(formulario.get("tipo") ?? "").trim();

  if (titulo.length < 3 || !tipo) {
    return { ok: false, mensagem: "Informe o título e o tipo do documento." };
  }

  const supabase = await clienteDoServidor();
  // Nome sem informação (ADR-0004 item 5): quem listar o bucket não lê o acervo
  // pelos nomes dos arquivos.
  const caminho = `${randomUUID()}.pdf`;
  // O id é gerado aqui, e o insert não pede `returning`: quem vai enviar o
  // arquivo já precisa do id, então a ida e volta não serve para nada.
  //
  // Havia um segundo motivo, hoje resolvido e digno de registro: a policy de
  // leitura de `documentos` chamava uma função `stable` que reconsultava a
  // tabela, e dentro do comando de insert essa releitura não enxerga a linha
  // nascendo — `insert ... returning` era recusado com 42501 para qualquer
  // papel, editora inclusive. Corrigido tornando o predicado local à linha
  // (migração `20260906100500`, mesmo princípio do ADR-0023).
  const documentoId = randomUUID();

  const { error } = await supabase.from("documentos").insert({
    id: documentoId,
    tipo,
    titulo,
    storage_bucket: "documentos",
    storage_path: caminho,
    status: "pendente",
  });

  if (error) {
    // A mensagem do banco é técnica demais para a tela, e vazaria detalhe de
    // policy. A causa quase sempre é uma só, e é acionável.
    return {
      ok: false,
      mensagem:
        "Não consegui registrar o documento. Confirme que você entrou com o segundo fator — publicar exige isso.",
    };
  }

  const { data: assinatura } = await clienteDeServico()
    .storage.from("documentos")
    .createSignedUploadUrl(caminho);

  if (!assinatura) {
    return { ok: false, mensagem: "Não consegui preparar o envio do arquivo." };
  }

  return {
    ok: true,
    documentoId,
    caminho,
    urlDeUpload: assinatura.signedUrl,
    token: assinatura.token,
  };
}

/**
 * O arquivo chegou ao bucket: agora o pipeline pode começar.
 *
 * Enfileirar é sempre `job.enfileirar` (ADR-0025 §2). A chamada vai por conexão
 * direta porque o schema `job` está fora do PostgREST de propósito — e continua
 * fora: nenhuma tela precisa ver a fila.
 */
export async function confirmarEnvio(documentoId: string): Promise<{ ok: boolean }> {
  const supabase = await clienteDoServidor();
  // Reconfirma pela RLS que esta pessoa enxerga o documento antes de criar
  // trabalho em nome dele. Sem isto, um id adivinhado enfileiraria processamento
  // de documento alheio — barulho, não vazamento, mas barulho evitável.
  const { data } = await supabase
    .from("documentos")
    .select("id")
    .eq("id", documentoId)
    .maybeSingle();

  if (!data) return { ok: false };

  await bancoDireto().query(
    `select job.enfileirar('hash_dedupe', $1::uuid, $2, '{}'::jsonb, 100)`,
    [documentoId, `hash_dedupe:${documentoId}:v1`],
  );

  revalidatePath("/acervo");
  return { ok: true };
}
