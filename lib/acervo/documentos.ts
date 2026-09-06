import "server-only";

import { clienteDoServidor } from "@/lib/supabase/servidor";
import { clienteDeServico } from "@/lib/supabase/servico";

/**
 * Leitura do acervo.
 *
 * Toda consulta aqui usa o cliente **do usuário**, nunca `service_role`: é a RLS
 * que decide o que cada pessoa enxerga (ADR-0012). Um documento que não aparece
 * não aparece porque o banco não devolveu a linha — não porque a tela filtrou.
 */

export interface DocumentoNaLista {
  id: string;
  tipo: string;
  titulo: string;
  data_documento: string | null;
  competencia: string | null;
  paginas: number | null;
  status: string;
  visibilidade: string;
  indexado: boolean;
}

export async function listaDocumentos(): Promise<DocumentoNaLista[]> {
  const supabase = await clienteDoServidor();
  const { data } = await supabase
    .from("documentos")
    .select(
      "id, tipo, titulo, data_documento, competencia, paginas, status, visibilidade",
    )
    .order("data_documento", { ascending: false, nullsFirst: false })
    .order("titulo");

  return (data ?? []).map((linha) => ({
    ...linha,
    indexado: linha.status === "publicado" || linha.status === "indexado",
  })) as DocumentoNaLista[];
}

export interface PaginaDoDocumento {
  pagina: number;
  texto: string | null;
  fonte_texto: string;
  confianca_ocr: number | null;
  visibilidade: string | null;
}

export interface DocumentoCompleto extends DocumentoNaLista {
  storage_bucket: string;
  storage_path: string;
  erro_detalhe: string | null;
  paginasTexto: PaginaDoDocumento[];
}

export async function carregaDocumento(id: string): Promise<DocumentoCompleto | null> {
  const supabase = await clienteDoServidor();

  const { data: documento } = await supabase
    .from("documentos")
    .select(
      "id, tipo, titulo, data_documento, competencia, paginas, status, visibilidade, storage_bucket, storage_path, erro_detalhe",
    )
    .eq("id", id)
    .maybeSingle();

  if (!documento) return null;

  // As páginas têm policy própria (`app.pagina_visivel`): num documento misto, a
  // pessoa vê as páginas públicas e não vê as demais. Por isso a lista de páginas
  // vem do banco filtrada, e não de um `slice` da nossa parte.
  const { data: paginas } = await supabase
    .from("documento_paginas")
    .select("pagina, texto, fonte_texto, confianca_ocr, visibilidade")
    .eq("documento_id", id)
    .order("pagina");

  return {
    ...(documento as Omit<DocumentoCompleto, "indexado" | "paginasTexto">),
    indexado: documento.status === "publicado" || documento.status === "indexado",
    paginasTexto: (paginas ?? []) as PaginaDoDocumento[],
  };
}

/**
 * URL assinada para o PDF original, com validade curta.
 *
 * A ordem importa e é a barreira de verdade (SPEC §7, dívida E1): primeiro
 * confirmamos que **este usuário** enxerga o documento — a consulta acima passa
 * pela RLS — e só então a chave de serviço assina a URL. Assinar primeiro e
 * checar depois entregaria o arquivo a quem não pode vê-lo, porque a URL
 * assinada não pergunta nada a ninguém.
 *
 * TTL de 5 minutos: tempo de abrir, não de compartilhar.
 */
export async function urlAssinadaDoOriginal(id: string): Promise<string | null> {
  const documento = await carregaDocumento(id);
  if (!documento) return null;

  const { data } = await clienteDeServico()
    .storage.from(documento.storage_bucket)
    .createSignedUrl(documento.storage_path, 300);

  return data?.signedUrl ?? null;
}
