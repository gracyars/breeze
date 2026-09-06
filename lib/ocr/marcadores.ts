/**
 * Normalização de marcador de lista em texto vindo de OCR.
 *
 * Por que isto existe, e por que não é polimento cosmético: a Convenção do Breeze
 * **não é articulada** (2 ocorrências de "Art." em 58 mil caracteres). A unidade
 * citável dela é `cláusula → item a) → subitem i.`, e o marcador do item é
 * exatamente o token que o OCR erra com mais frequência — string de uma ou duas
 * letras é ambígua por natureza para o reconhecedor. Medição em
 * `docs/ocr/medicao-vision-convencao.md`: `ii.` sai como `il.`, `iii.` como `li.`,
 * `o)` como `0)`.
 *
 * Citar "item ii" quando o documento diz "item iii" é o erro que destrói a
 * credibilidade do produto tão rápido quanto um dígito errado em balancete — e é
 * mais difícil de perceber, porque o texto ao redor está certo.
 *
 * Regra de segurança do módulo: **só corrige o que a sequência prova.** Um
 * marcador só é reescrito quando não continua nenhuma sequência aberta, é
 * leitura errada do sucessor de exatamente uma delas sob as classes de confusão
 * medidas, e não é ele próprio um marcador válido. Fora disso o marcador é
 * preservado e a linha é marcada para conferência humana — nunca adivinhada.
 *
 * As três travas nasceram de erros contra o texto real, não de hipótese; cada
 * uma está documentada onde é aplicada. A validação que importa não foi o teste
 * unitário: foi rodar sobre as 945 linhas da Convenção e ler as 26 correções uma
 * a uma. As primeiras versões acertavam 41 e corrompiam 3.
 */

/** Classes de confusão do reconhecedor: caracteres que ele troca entre si. */
const CLASSES_DE_CONFUSAO = [
  "il1|íıI",
  "o0O°",
  "s5S$",
  "g9q",
  "cC(ç",
  "kK",
  "vV",
  "xX",
  "zZ2",
  "bB6",
  "uUµ",
] as const;

const CANONICO = new Map<string, string>();
for (const classe of CLASSES_DE_CONFUSAO) {
  for (const caractere of classe) CANONICO.set(caractere, classe[0]);
}

/** Reduz um marcador à sua forma canônica sob as classes de confusão. */
function canonizar(marcador: string): string {
  let saida = "";
  for (const caractere of marcador.toLowerCase()) {
    saida += CANONICO.get(caractere) ?? caractere;
  }
  return saida;
}

/** Um token é o outro com exatamente um caractere a menos? */
function difereEmUmCaractere(a: string, b: string): boolean {
  if (Math.abs(a.length - b.length) !== 1) return false;
  const [curto, longo] = a.length < b.length ? [a, b] : [b, a];
  for (let i = 0; i <= curto.length; i += 1) {
    if (curto.slice(0, i) === longo.slice(0, i) && curto.slice(i) === longo.slice(i + 1)) {
      return true;
    }
  }
  return false;
}

/**
 * O marcador lido é plausivelmente o esperado, lido errado?
 *
 * Duas tolerâncias, e só duas. **Troca** de caractere vale apenas dentro das
 * classes de confusão — a canonização já resolveu isso, então depois dela a
 * igualdade tem de ser exata. **Perda** de um caractere é tolerada, porque é o
 * erro medido: `iii.` chega como `li.`, o reconhecedor funde dois `i` num `l` e o
 * token encurta.
 *
 * Duas travas, ambas escritas depois de o módulo errar contra o texto real:
 *
 * - `Il.` (que é `II.`, título de capítulo) canoniza para `ii` e, sob distância
 *   de edição livre, virava `iv.` — um `i` trocado por um `v` que reconhecedor
 *   nenhum troca. Por isso troca fora das classes medidas não passa.
 * - **Token que já é um marcador válido da família nunca é reescrito.** Quando um
 *   marcador se perde no meio da lista, a contagem dessincroniza e todos os itens
 *   seguintes — que estão corretos — passam a "sobrar um" em relação ao esperado.
 *   Sem esta trava, o módulo reescrevia `xvi.` para `xv.`, `xvii.` para `xvi.` e
 *   assim por diante, corrompendo em cascata a numeração de uma convenção a
 *   partir de um único item que o OCR não leu. Dessincronizado, o certo é
 *   sinalizar a lacuna, não renumerar o documento.
 */
function ehLeituraErrada(
  bruto: string,
  esperado: string,
  familia: FamiliaDeMarcador,
): boolean {
  const a = canonizar(bruto);
  const b = canonizar(esperado);
  if (a === b) return true;
  if (posicaoNaFamilia(bruto, familia) > 0) return false;
  return a.length === b.length - 1 && difereEmUmCaractere(a, b);
}

export type FamiliaDeMarcador = "letra" | "romano" | "arabico";

const ROMANOS = [
  "i", "ii", "iii", "iv", "v", "vi", "vii", "viii", "ix", "x",
  "xi", "xii", "xiii", "xiv", "xv", "xvi", "xvii", "xviii", "xix", "xx",
] as const;

const LETRAS = "abcdefghijklmnopqrstuvwxyz";

/**
 * Posição (1-based) de um marcador dentro da sua família, ou 0 se não pertence.
 *
 * "i" é ambíguo — é tanto a 1ª letra romana quanto a 9ª letra do alfabeto. A
 * ambiguidade é resolvida pela sequência aberta, não aqui.
 */
function posicaoNaFamilia(
  marcador: string,
  familia: FamiliaDeMarcador,
): number {
  const bruto = marcador.toLowerCase();
  if (familia === "romano") return ROMANOS.indexOf(bruto as (typeof ROMANOS)[number]) + 1;
  if (familia === "letra") return bruto.length === 1 ? LETRAS.indexOf(bruto) + 1 : 0;
  return /^\d{1,3}$/.test(bruto) ? Number.parseInt(bruto, 10) : 0;
}

function marcadorNaPosicao(
  posicao: number,
  familia: FamiliaDeMarcador,
  maiuscula: boolean,
): string | null {
  if (posicao < 1) return null;
  let base: string;
  if (familia === "romano") {
    if (posicao > ROMANOS.length) return null;
    base = ROMANOS[posicao - 1];
  } else if (familia === "letra") {
    if (posicao > LETRAS.length) return null;
    base = LETRAS[posicao - 1];
  } else {
    base = String(posicao);
  }
  return maiuscula ? base.toUpperCase() : base;
}

/** `i.`, `a)`, `12)` no início da linha — com o espaço que separa do texto. */
const INICIO_DE_ITEM = /^(\s*)([0-9A-Za-zÀ-ÿ|ı]{1,5})([.)])(\s|$)/;

export type Suspeita = "marcador_ausente" | "marcador_fora_de_sequencia";

export interface LinhaNormalizada {
  /** Texto final: igual à entrada, exceto pelo marcador reescrito. */
  texto: string;
  /** Texto exatamente como o OCR entregou — preservado para diagnóstico. */
  textoOriginal: string;
  /** Marcador aceito depois da normalização, sem o delimitador. */
  marcador?: string;
  familia?: FamiliaDeMarcador;
  /** Verdadeiro quando este módulo reescreveu o marcador. */
  corrigido: boolean;
  /** O que a conferência humana precisa olhar nesta linha. */
  suspeita?: Suspeita;
}

interface Sequencia {
  familia: FamiliaDeMarcador;
  delimitador: string;
  maiuscula: boolean;
  ultimaPosicao: number;
}

/**
 * Normaliza os marcadores de lista de uma página de OCR.
 *
 * Recebe as linhas na ordem de leitura e devolve, por linha, o texto corrigido e
 * o que ficou suspeito. Não altera nada além do marcador: o corpo do texto sai
 * intocado, porque quem confere precisa comparar com o PDF sem ruído nosso.
 */
export function normalizaMarcadores(linhas: readonly string[]): LinhaNormalizada[] {
  const abertas = new Map<string, Sequencia>();
  const saida: LinhaNormalizada[] = [];

  for (const linha of linhas) {
    const casamento = INICIO_DE_ITEM.exec(linha);
    if (!casamento) {
      saida.push({ texto: linha, textoOriginal: linha, corrigido: false });
      continue;
    }

    const [, espacos, bruto, delimitador, sufixo] = casamento;
    const maiuscula = bruto === bruto.toUpperCase() && /[a-zA-Z]/.test(bruto);

    // 1. O marcador continua alguma sequência aberta exatamente como veio —
    //    inclusive na caixa. Caixa é nível, não estilo: numa convenção, `II.` é
    //    título de capítulo e `ii.` é subitem dentro de uma cláusula. Tratar as
    //    duas como a mesma lista foi o erro que a primeira versão deste módulo
    //    cometeu contra o texto real (transformou "VI. ADMINISTRAÇÃO DO
    //    CONDOMÍNIO" em "ii. ADMINISTRAÇÃO DO CONDOMÍNIO").
    let continuacao: Sequencia | null = null;
    for (const sequencia of abertas.values()) {
      if (sequencia.delimitador !== delimitador) continue;
      const esperado = marcadorNaPosicao(
        sequencia.ultimaPosicao + 1,
        sequencia.familia,
        sequencia.maiuscula,
      );
      if (esperado === bruto) {
        continuacao = sequencia;
        break;
      }
    }

    if (continuacao) {
      continuacao.ultimaPosicao += 1;
      saida.push({
        texto: linha,
        textoOriginal: linha,
        marcador: bruto,
        familia: continuacao.familia,
        corrigido: false,
      });
      continue;
    }

    // 2. Não continua nada. É confusão de OCR do sucessor esperado de exatamente
    //    uma sequência aberta? Mais de uma candidata = ambíguo = não mexe.
    //
    //    Caixa divergente só é tolerada em marcador de um caractere (`K)` no meio
    //    de uma lista em minúscula é ruído do reconhecedor). De dois caracteres
    //    para cima, caixa diferente significa outro nível da hierarquia, e
    //    atravessar nível reescreveria um título como se fosse item.
    const candidatos: { sequencia: Sequencia; esperado: string }[] = [];
    for (const sequencia of abertas.values()) {
      if (sequencia.delimitador !== delimitador) continue;
      const esperado = marcadorNaPosicao(
        sequencia.ultimaPosicao + 1,
        sequencia.familia,
        sequencia.maiuscula,
      );
      if (!esperado || !ehLeituraErrada(bruto, esperado, sequencia.familia)) continue;
      if (sequencia.maiuscula !== maiuscula && esperado.length > 1) continue;
      // `i.`, `a)` ou `1)` legíveis são reinício de lista tão provavelmente
      // quanto leitura errada do sucessor — e reescrever um reinício empurra
      // toda a numeração seguinte para o lugar errado, em cascata. Deixa passar.
      if (posicaoNaFamilia(bruto, sequencia.familia) === 1) continue;
      candidatos.push({ sequencia, esperado });
    }

    if (candidatos.length === 1) {
      const { sequencia, esperado } = candidatos[0];
      sequencia.ultimaPosicao += 1;
      const texto = `${espacos}${esperado}${delimitador}${sufixo}${linha.slice(casamento[0].length)}`;
      saida.push({
        texto,
        textoOriginal: linha,
        marcador: esperado,
        familia: sequencia.familia,
        corrigido: true,
      });
      continue;
    }

    // 3. Abre (ou reabre) sequência. Um marcador de 1ª posição é começo legítimo;
    //    qualquer outro salto fica marcado para conferência, nunca adivinhado.
    // `i` é ambíguo (1º romano ou 9ª letra) e `v`/`x` também. Na abertura de uma
    // sequência, romano ganha: começar uma lista de letras direto no "v)" não
    // acontece em documento real, e a continuação de uma lista de letras já teria
    // sido resolvida nos passos 1 e 2, onde a sequência aberta desfaz a ambiguidade.
    const familia: FamiliaDeMarcador =
      posicaoNaFamilia(bruto, "romano") > 0
        ? "romano"
        : posicaoNaFamilia(bruto, "arabico") > 0
          ? "arabico"
          : "letra";

    const posicao = posicaoNaFamilia(bruto, familia);
    if (posicao === 0) {
      saida.push({ texto: linha, textoOriginal: linha, corrigido: false });
      continue;
    }

    const chave = `${familia}${delimitador}${maiuscula ? "MAI" : "min"}`;
    const anterior = abertas.get(chave);
    const salto = anterior !== undefined && posicao > anterior.ultimaPosicao + 1;
    // Marcador que anda para trás ou repete o anterior: na página 14 da Convenção
    // o `iii.` do fundo de reserva chega como `ii.`, repetindo o item acima. O
    // módulo não reescreve (é marcador válido, e reescrever renumeraria o resto),
    // mas ficar calado seria pior — sem sinal, a conferência não olha a linha.
    const repeticao =
      anterior !== undefined && posicao <= anterior.ultimaPosicao && posicao > 1;
    abertas.set(chave, {
      familia,
      delimitador,
      maiuscula,
      ultimaPosicao: posicao,
    });

    saida.push({
      texto: linha,
      textoOriginal: linha,
      marcador: bruto,
      familia,
      corrigido: false,
      suspeita: salto
        ? "marcador_ausente"
        : repeticao || (posicao > 1 && anterior === undefined)
          ? "marcador_fora_de_sequencia"
          : undefined,
    });
  }

  return saida;
}

/**
 * `49,68 m?` → `49,68 m²`. O reconhecedor não devolve expoente, e "m?" não existe
 * em texto de convenção. Só aplica depois de número, para não reescrever uma
 * interrogação legítima.
 *
 * A área em si continua sendo número vindo de OCR: entra como proposta, não como
 * dado publicável (SPEC §5.1, ADR-0006). Isto conserta a unidade, não o valor.
 */
export function normalizaUnidadeDeArea(texto: string): string {
  return texto.replace(/(\d)(\s*)m[?2](?![\w²])/g, "$1$2m²");
}
