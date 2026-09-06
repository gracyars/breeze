/**
 * Deduplicação de resultado por conteúdo repetido no acervo (ADR-0028).
 *
 * O caso é real e está no acervo desde o primeiro dia: a ata da AGE de
 * 04.02.2026 embute o Regimento Interno inteiro como anexo. Buscar "animais
 * domésticos" devolve o mesmo texto duas vezes — uma no Regimento, outra dentro
 * da ata — e o morador não tem como saber que são a mesma regra, nem qual citar.
 *
 * Duas regras, e a segunda é a que importa:
 *
 * 1. **Isto é ranking, não autorização.** Roda **depois** da RLS, sobre o que o
 *    banco já devolveu. Deduplicar dentro de uma policy criaria de novo a
 *    não-localidade do ADR-0023 — decidir sobre uma linha lendo outras — pela
 *    terceira vez no projeto.
 * 2. **O canônico é o documento normativo, não o que prova o ato.** A ata prova
 *    que o regimento foi aprovado; quem *diz a regra* é o regimento. Citar "Cap.
 *    V, Art. 1º da ata da AGE" manda o morador procurar a regra no lugar errado.
 *
 * A cópia suprimida não some: ela vira uma nota no resultado que sobreviveu
 * ("aparece também em…"), porque saber que a regra está anexada à ata é
 * informação útil numa assembleia.
 */

/** Tipos que dizem a regra. Quem não está aqui só a reproduz. */
const CANONICOS = new Set(["convencao", "regimento"]);

export interface Deduplicavel {
  chunkId: string;
  documentoId: string;
  titulo: string;
  tipo: string;
  texto: string;
  rank: number;
}

export interface ResultadoDeduplicado<T extends Deduplicavel> {
  resultado: T;
  /** Documentos onde o mesmo conteúdo também aparece. */
  tambemEm: { documentoId: string; titulo: string }[];
}

/**
 * Assinatura de conteúdo: conjunto de trigramas de palavra.
 *
 * Palavra e não caractere porque o que se quer detectar é "mesmo texto", não
 * "texto parecido"; e trigrama e não hash do texto inteiro porque as duas cópias
 * nunca são idênticas — a fronteira de chunk cai em lugar diferente em cada
 * documento, e o OCR de uma delas pode ter passado por normalização.
 */
export function assinatura(texto: string): Set<string> {
  const palavras = texto
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "")
    .toLowerCase()
    .replace(/[^\p{L}\p{N}\s]/gu, " ")
    .split(/\s+/)
    .filter((p) => p.length > 2);

  const trigramas = new Set<string>();
  for (let i = 0; i + 2 < palavras.length; i += 1) {
    trigramas.add(`${palavras[i]} ${palavras[i + 1]} ${palavras[i + 2]}`);
  }
  return trigramas;
}

/** Jaccard entre dois conjuntos de trigramas. */
export function semelhanca(a: Set<string>, b: Set<string>): number {
  if (a.size === 0 || b.size === 0) return 0;
  let intersecao = 0;
  const [menor, maior] = a.size <= b.size ? [a, b] : [b, a];
  for (const item of menor) if (maior.has(item)) intersecao += 1;
  return intersecao / (a.size + b.size - intersecao);
}

/**
 * Limiar deliberadamente alto.
 *
 * 0,6 de Jaccard sobre trigramas de palavra é "isto é literalmente o mesmo
 * texto", não "isto fala do mesmo assunto". Dois artigos diferentes sobre
 * churrasqueira compartilham vocabulário e ficam bem abaixo disso. Errar para
 * baixo esconde resultado legítimo — pior que mostrar duplicata.
 */
export const LIMIAR_DE_DUPLICATA = 0.6;

export function deduplica<T extends Deduplicavel>(
  resultados: readonly T[],
  limiar = LIMIAR_DE_DUPLICATA,
): ResultadoDeduplicado<T>[] {
  const assinaturas = resultados.map((r) => assinatura(r.texto));
  const saida: ResultadoDeduplicado<T>[] = [];
  const absorvidos = new Set<number>();

  resultados.forEach((resultado, i) => {
    if (absorvidos.has(i)) return;

    let escolhido = resultado;
    let indiceEscolhido = i;
    const tambemEm: { documentoId: string; titulo: string }[] = [];

    for (let j = i + 1; j < resultados.length; j += 1) {
      if (absorvidos.has(j)) continue;
      const outro = resultados[j];
      // Repetição dentro do mesmo documento é estrutura do documento (sobreposição
      // de chunk), não anexo replicado — não é disto que se trata aqui.
      if (outro.documentoId === escolhido.documentoId) continue;
      if (semelhanca(assinaturas[indiceEscolhido], assinaturas[j]) < limiar) continue;

      absorvidos.add(j);
      // O normativo ganha, mesmo que tenha vindo pior no ranking: a regra é dita
      // por ele, e a citação tem de apontar para onde a regra está.
      if (!CANONICOS.has(escolhido.tipo) && CANONICOS.has(outro.tipo)) {
        tambemEm.push({ documentoId: escolhido.documentoId, titulo: escolhido.titulo });
        escolhido = outro;
        indiceEscolhido = j;
      } else {
        tambemEm.push({ documentoId: outro.documentoId, titulo: outro.titulo });
      }
    }

    saida.push({ resultado: escolhido, tambemEm });
  });

  return saida;
}
