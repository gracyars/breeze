import "server-only";

import { expandeSinonimos, pareceIdentificador, type Sinonimo } from "@/lib/busca/consulta";
import { clienteDoServidor } from "@/lib/supabase/servidor";

/**
 * Execução da busca.
 *
 * **F1 entrega só a metade léxica** (`tsvector` com a configuração `public.pt_br`).
 * A metade semântica existe no desenho e nasce desligada (ADR-0027, D18): sem
 * chave de LLM não há embedding, e fingir que a busca está completa seria pior
 * que dizer que está pela metade. Por isso `metadeSemanticaLigada` sai daqui e
 * vai para a tela — o acervo que responde pela metade sem avisar é o modo de
 * falha que a decisão explicitamente proíbe.
 *
 * A RLS continua sendo a fronteira: a função no banco é `security invoker`, então
 * cada pessoa busca dentro do que ela pode ler. Um chunk de página que ela não
 * enxerga não é filtrado pela tela — não volta do banco.
 */

export interface Resultado {
  chunkId: string;
  documentoId: string;
  titulo: string;
  tipo: string;
  paginaIni: number;
  paginaFim: number;
  secao: string | null;
  /** Trecho literal com os termos marcados — é o resultado primário na tela. */
  trecho: string;
  rank: number;
}

export interface RespostaDaBusca {
  consultaOriginal: string;
  consultaExpandida: string;
  resultados: Resultado[];
  metadeSemanticaLigada: boolean;
  ehIdentificador: boolean;
}

export async function busca(
  consulta: string,
  limite = 10,
): Promise<RespostaDaBusca> {
  const supabase = await clienteDoServidor();

  const { data: linhas } = await supabase
    .from("sinonimos")
    .select("termo_normalizado, expansoes")
    .eq("ativo", true);

  const sinonimos: Sinonimo[] = (linhas ?? []).map((linha) => ({
    termoNormalizado: linha.termo_normalizado ?? "",
    expansoes: linha.expansoes ?? [],
  }));

  const expandida = expandeSinonimos(consulta, sinonimos);

  const { data } = await supabase.rpc("buscar_lexica", {
    p_consulta: expandida,
    p_limite: limite,
  });

  const resultados: Resultado[] = (
    (data ?? []) as {
      chunk_id: string;
      documento_id: string;
      titulo: string;
      tipo: string;
      pagina_ini: number;
      pagina_fim: number;
      secao: string | null;
      trecho: string;
      rank: number;
    }[]
  ).map((linha) => ({
    chunkId: linha.chunk_id,
    documentoId: linha.documento_id,
    titulo: linha.titulo,
    tipo: linha.tipo,
    paginaIni: linha.pagina_ini,
    paginaFim: linha.pagina_fim,
    secao: linha.secao,
    trecho: linha.trecho,
    rank: linha.rank,
  }));

  return {
    consultaOriginal: consulta,
    consultaExpandida: expandida,
    resultados,
    metadeSemanticaLigada: Boolean(process.env.LLM_API_KEY),
    ehIdentificador: pareceIdentificador(consulta),
  };
}

/**
 * Referência citável de um resultado.
 *
 * O formato tem de bastar para alguém conferir no PDF **sem** confiar em nós:
 * documento, capítulo quando existe, e página. O capítulo não é enfeite — o
 * Regimento do Breeze reinicia a numeração de artigo a cada capítulo, então
 * "Artigo 5º" sozinho aponta para 24 lugares diferentes.
 */
export function referencia(resultado: Resultado): string {
  const paginas =
    resultado.paginaIni === resultado.paginaFim
      ? `p. ${resultado.paginaIni}`
      : `p. ${resultado.paginaIni}–${resultado.paginaFim}`;
  return [resultado.titulo, resultado.secao, paginas].filter(Boolean).join(" · ");
}
