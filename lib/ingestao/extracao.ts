import { extractText, getDocumentProxy } from "unpdf";

/**
 * Estágio 2 do pipeline (ADR-0025): extração nativa, página a página.
 *
 * A saída é **proposta**, não publicação. `texto_nativo` guarda o que o PDF
 * trazia e nunca é sobrescrito (ADR-0024): OCR só substitui `texto` quando o
 * nativo é vazio ou quando a editora mandou. Reverter é trocar `texto` de volta,
 * sem reprocessar nada.
 */

export type FonteDeTexto = "nativo" | "ocr" | "misto" | "vazio";

export interface PaginaExtraida {
  pagina: number;
  textoNativo: string;
  /** Texto efetivo desta passada — igual ao nativo aqui; o OCR entra no estágio 3. */
  texto: string;
  fonteTexto: FonteDeTexto;
  /** Caracteres úteis: sem espaço em branco repetido nem pontilhado de sumário. */
  caracteresUteis: number;
  /** Proporção de tokens que não parecem palavra em português. */
  razaoIlegivel: number;
}

export interface DocumentoExtraido {
  paginas: PaginaExtraida[];
  totalPaginas: number;
}

export interface LimiaresDeOcr {
  /** Abaixo disto a página é tratada como vazia e o OCR dispara sozinho. */
  caracteresMinimos: number;
  /** Acima disto a página vira proposta de OCR para a curadoria — nunca ação. */
  razaoIlegivelMaxima: number;
}

/**
 * Padrão de fábrica. **Os valores reais vivem em `configuracoes`** (ADR-0006,
 * mantido pelo ADR-0024): estes existem para o código rodar sem banco em teste,
 * não para governar produção.
 */
export const LIMIARES_PADRAO: LimiaresDeOcr = {
  caracteresMinimos: 8,
  razaoIlegivelMaxima: 0.35,
};

export async function extraiTextoNativo(
  pdf: Uint8Array,
  limiares: LimiaresDeOcr = LIMIARES_PADRAO,
): Promise<DocumentoExtraido> {
  const documento = await getDocumentProxy(pdf);
  const { totalPages, text } = await extractText(documento, { mergePages: false });

  const paginas = text.map((bruto, indice) => {
    const textoNativo = bruto ?? "";
    const uteis = caracteresUteis(textoNativo);
    const vazia = uteis < limiares.caracteresMinimos;
    return {
      pagina: indice + 1,
      textoNativo,
      texto: vazia ? "" : textoNativo,
      fonteTexto: (vazia ? "vazio" : "nativo") as FonteDeTexto,
      caracteresUteis: uteis,
      razaoIlegivel: razaoIlegivel(textoNativo),
    };
  });

  return { paginas, totalPaginas: totalPages };
}

/**
 * Conta o que é texto de verdade.
 *
 * Sumário com pontilhado (`Capítulo I .......... 3`) e capa com letra espaçada
 * enganam a contagem crua — foram 6 dos 43 documentos do acervo real sinalizados
 * à toa pela heurística antiga. Aqui pontilhado e espaço repetido não contam.
 */
export function caracteresUteis(texto: string): number {
  return texto
    .replace(/[.·•‥…]{3,}/g, "")
    .replace(/\s+/g, " ")
    .trim().length;
}

/**
 * Fração de tokens que não parecem palavra em português.
 *
 * **Só sinaliza; não decide.** Disparar OCR automático nesta faixa sobrescreveria
 * texto nativo correto — a degradação que o ADR-0006 queria evitar e que, com OCR
 * local, sai de graça e por isso é ainda mais tentadora. A tela de conferência
 * pergunta; a editora responde. Custo do erro: um clique.
 */
export function razaoIlegivel(texto: string): number {
  const tokens = texto
    .replace(/[.·•‥…]{3,}/g, " ")
    .split(/\s+/)
    .filter((t) => t.length > 1);
  if (tokens.length === 0) return 0;

  const suspeitos = tokens.filter((token) => {
    const letras = token.replace(/[^\p{L}]/gu, "");
    if (letras.length < 2) return false;
    // Sem vogal nenhuma, ou cinco consoantes seguidas: não é palavra do PT-BR.
    return (
      !/[aeiouáàâãéêíóôõúü]/i.test(letras) ||
      /[bcdfghjklmnpqrstvwxyzç]{5,}/i.test(letras)
    );
  });

  return suspeitos.length / tokens.length;
}

/** A página precisa de OCR agora, sem perguntar? Só quando não há o que degradar. */
export function exigeOcrAutomatico(pagina: PaginaExtraida): boolean {
  return pagina.fonteTexto === "vazio";
}

/** A página merece a pergunta "rodar OCR?" na tela de conferência? */
export function proporOcrNaConferencia(
  pagina: PaginaExtraida,
  limiares: LimiaresDeOcr = LIMIARES_PADRAO,
): boolean {
  return (
    pagina.fonteTexto === "nativo" && pagina.razaoIlegivel > limiares.razaoIlegivelMaxima
  );
}
