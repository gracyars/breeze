import "server-only";

import { clienteDoServidor } from "@/lib/supabase/servidor";

/**
 * A fila de conferência.
 *
 * O fato dominante é que existe **uma** editora, humana, e ela é o gargalo de
 * publicação (D4). Se conferir for enfadonho, o produto morre de backlog — não
 * por defeito, por desistência. Daí o desenho do ADR-0029 §3, que este módulo
 * implementa: fila e não lista, ordem por valor e não alfabética, parar no meio
 * é normal, e nada bloqueia nada.
 */

/**
 * Ordem por valor entregue, não por nome de arquivo.
 *
 * As primeiras conferências têm de produzir produto: o Regimento é a peça-chave
 * e o documento canônico para citação; a Convenção é o único público; atas e
 * balancetes são o que o morador procura. Conferir 43 documentos em ordem
 * alfabética faria a mantenedora gastar as dez primeiras horas em comunicado de
 * churrasqueira.
 */
const PESO_POR_TIPO: Record<string, number> = {
  regimento: 1,
  convencao: 2,
  ata_assembleia: 3,
  balancete: 4,
  prestacao_contas: 5,
  previsao_orcamentaria: 6,
  edital_convocacao: 7,
  demonstrativo_cota: 8,
};

export interface ItemDaFila {
  id: string;
  tipo: string;
  titulo: string;
  status: string;
  visibilidade: string;
  paginas: number | null;
  erro_detalhe: string | null;
  data_documento: string | null;
}

/**
 * O que ainda espera decisão humana.
 *
 * Documento em `erro` **fica na fila**, com o erro à vista — sumir seria a
 * falha silenciosa outra vez, agora na tela.
 */
export async function filaDeConferencia(): Promise<ItemDaFila[]> {
  const supabase = await clienteDoServidor();
  const { data } = await supabase
    .from("documentos")
    .select(
      "id, tipo, titulo, status, visibilidade, paginas, erro_detalhe, data_documento",
    )
    .in("status", ["em_revisao", "erro", "indexado", "pendente", "processando"]);

  return ((data ?? []) as ItemDaFila[]).sort((a, b) => {
    const pesoA = PESO_POR_TIPO[a.tipo] ?? 9;
    const pesoB = PESO_POR_TIPO[b.tipo] ?? 9;
    if (pesoA !== pesoB) return pesoA - pesoB;
    return (a.data_documento ?? a.titulo).localeCompare(b.data_documento ?? b.titulo);
  });
}

export interface Progresso {
  publicados: number;
  aguardando: number;
  total: number;
}

/** "12 de 43" — contador é o que faz a fila parecer progresso, e não dever de casa. */
export async function progresso(): Promise<Progresso> {
  const supabase = await clienteDoServidor();
  const { data } = await supabase.from("documentos").select("status");
  const linhas = (data ?? []) as { status: string }[];

  const publicados = linhas.filter((l) => l.status === "publicado").length;
  return {
    publicados,
    aguardando: linhas.length - publicados,
    total: linhas.length,
  };
}
