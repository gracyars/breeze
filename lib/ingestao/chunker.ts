/**
 * Estágio 4 do pipeline (ADR-0025): chunking ciente de página **e de
 * visibilidade**.
 *
 * A regra que molda tudo aqui está no SPEC §3 e no ADR-0021: **um chunk não pode
 * atravessar fronteira de visibilidade.** E com ~15% de sobreposição ele
 * atravessa página por construção — então a fronteira tem de ser respeitada pelo
 * chunker, não descoberta pelo trigger que rejeita a inserção.
 *
 * Por que isso não é teórico: a ata da AGE de 04.02.2026 embute o Regimento
 * Interno inteiro como anexo. A ata é autenticada, o Regimento é público. Sem
 * esta regra, um chunk com 15% de sobreposição costura as duas coisas e a busca
 * pública passa a devolver texto de documento autenticado — sem ninguém ter
 * mudado nenhuma policy.
 *
 * A ordem real do fluxo é chunkizar primeiro e classificar visibilidade depois
 * (a curadoria marca as páginas em seguida). Por isso reclassificar página apaga
 * os chunks que a intersectam e reenfileira o documento: o derivado é invalidado,
 * não o fluxo bloqueado.
 */

export interface PaginaParaChunk {
  pagina: number;
  texto: string;
  /** `null` = herda a visibilidade do documento. É o caso comum. */
  visibilidade: string | null;
}

export interface Chunk {
  ordem: number;
  paginaIni: number;
  paginaFim: number;
  texto: string;
  tokens: number;
  /** Visibilidade efetiva da faixa que originou o chunk — para conferência. */
  visibilidade: string;
  /**
   * Capítulo/seção em vigor no início do chunk, quando o documento tem essa
   * estrutura. É o que desambigua a citação em documento que reinicia a
   * numeração de artigo a cada capítulo — o caso do Regimento do Breeze.
   */
  secao: string | null;
}

export interface OpcoesDeChunk {
  /** SPEC §3.4: 800–1.200 tokens. */
  tokensMinimos: number;
  tokensMaximos: number;
  /** Fração do chunk anterior repetida no seguinte. */
  sobreposicao: number;
}

export const OPCOES_PADRAO: OpcoesDeChunk = {
  tokensMinimos: 800,
  tokensMaximos: 1200,
  sobreposicao: 0.15,
};

/**
 * Estimativa de tokens, deliberadamente grosseira.
 *
 * Não há tokenizador do modelo aqui — e não deve haver: trocar de modelo não pode
 * mudar a fronteira dos chunks, porque isso mudaria `versao_pipeline` e
 * obrigaria a reindexar o acervo por um motivo que não é o texto (ADR-0027).
 * Média de ~4 caracteres por token em português.
 */
export function estimaTokens(texto: string): number {
  return Math.ceil(texto.trim().length / 4);
}

/** Linha que é começo de unidade citável — o lugar preferido para cortar. */
function ehFronteiraDeSecao(linha: string): boolean {
  const t = linha.trim();
  if (t.length === 0) return false;
  return (
    /^Art(igo)?\.?\s*\d+/i.test(t) ||
    /^(CAP[IÍ]TULO|T[IÍ]TULO|SE[ÇC][ÃA]O|ANEXO)\b/i.test(t) ||
    /^[IVXL]{1,5}\s*[.)]\s+\S/.test(t) ||
    /^\d{1,2}\s*[.)]\s+\S/.test(t) ||
    /^[a-z]\)\s+\S/.test(t) ||
    /^Par[áa]grafo\b/i.test(t) ||
    // Título em caixa alta curto (a Convenção usa isso nos capítulos).
    (t === t.toUpperCase() && /\p{L}/u.test(t) && t.length <= 60)
  );
}

/**
 * Título de capítulo/seção — o contexto sem o qual a citação do Regimento é
 * ambígua.
 *
 * Medido no documento real: o Regimento Interno do Breeze tem 24 capítulos e
 * **reinicia a numeração de artigo em cada um**. Existem 24 "Artigo 1º" e
 * 187 linhas de artigo para apenas 25 números distintos. Citar "Artigo 5º do
 * Regimento" não identifica nada — só "Cap. XIII – PISCINA, Artigo 5º" identifica.
 * Por isso o capítulo viaja com o chunk: é parte da citação, não decoração.
 *
 * O documento escreve o romano ANTES da palavra ("I. CAPÍTULO – DISPOSIÇÕES
 * GERAIS") e às vezes omite a palavra ("XXI. LAVANDERIA COMPARTILHADA NOS
 * ANDARES"). Daí a segunda alternativa do reconhecedor. A exigência de caixa alta
 * é o que impede que uma frase terminada em "capítulo." vire título.
 */
function ehTituloDeSecao(linha: string): boolean {
  const t = linha.trim();
  if (t.length < 8 || t.length > 90) return false;
  const semAcento = t.normalize("NFD").replace(/[̀-ͯ]/g, "");
  const caixaAlta = semAcento === semAcento.toUpperCase();
  if (!caixaAlta) return false;
  return (
    /^(CAP[IÍ]TULO|T[IÍ]TULO|SE[ÇC][ÃA]O)\b/.test(t) ||
    /^[IVXL]{1,6}\s*[.)–-]\s*\S/.test(t)
  );
}

interface Bloco {
  texto: string;
  pagina: number;
  tokens: number;
  fronteira: boolean;
  /** Capítulo/seção vigente quando este bloco aparece. */
  secao: string | null;
}

/**
 * Divide as páginas em blocos com origem rastreada.
 *
 * A página é preservada por bloco porque é dela que sai `pagina_ini/pagina_fim`,
 * e é a página que a citação mostra. Perder isso aqui é perder a citação lá.
 */
function blocosDaFaixa(paginas: readonly PaginaParaChunk[]): Bloco[] {
  const blocos: Bloco[] = [];
  let secao: string | null = null;
  for (const pagina of paginas) {
    for (const linha of pagina.texto.split(/\n/)) {
      const texto = linha.trim();
      if (!texto) continue;
      if (ehTituloDeSecao(texto)) secao = texto;
      blocos.push({
        texto,
        pagina: pagina.pagina,
        tokens: estimaTokens(texto),
        fronteira: ehFronteiraDeSecao(texto),
        secao,
      });
    }
  }
  return blocos;
}

/**
 * Agrupa páginas consecutivas de mesma visibilidade efetiva.
 *
 * Esta função é a fronteira dura do módulo: nada que ela separa volta a se juntar
 * depois.
 */
function faixasPorVisibilidade(
  paginas: readonly PaginaParaChunk[],
  visibilidadeDoDocumento: string,
): { visibilidade: string; paginas: PaginaParaChunk[] }[] {
  const faixas: { visibilidade: string; paginas: PaginaParaChunk[] }[] = [];
  for (const pagina of paginas) {
    const efetiva = pagina.visibilidade ?? visibilidadeDoDocumento;
    const ultima = faixas.at(-1);
    if (ultima && ultima.visibilidade === efetiva) {
      ultima.paginas.push(pagina);
    } else {
      faixas.push({ visibilidade: efetiva, paginas: [pagina] });
    }
  }
  return faixas;
}

export function chunkiza(
  paginas: readonly PaginaParaChunk[],
  visibilidadeDoDocumento: string,
  opcoes: OpcoesDeChunk = OPCOES_PADRAO,
): Chunk[] {
  const chunks: Chunk[] = [];
  let ordem = 0;

  for (const faixa of faixasPorVisibilidade(paginas, visibilidadeDoDocumento)) {
    for (const blocos of porSecao(blocosDaFaixa(faixa.paginas))) {
      let inicio = 0;

      while (inicio < blocos.length) {
        let fim = inicio;
        let tokens = 0;
        let ultimaFronteira = -1;

        while (
          fim < blocos.length &&
          tokens + blocos[fim].tokens <= opcoes.tokensMaximos
        ) {
          tokens += blocos[fim].tokens;
          fim += 1;
          // Guarda o último corte "bonito" já alcançado depois do mínimo.
          if (
            tokens >= opcoes.tokensMinimos &&
            fim < blocos.length &&
            blocos[fim].fronteira
          ) {
            ultimaFronteira = fim;
          }
        }

        // Prefere terminar num começo de artigo/item; se não houver, corta no
        // limite de tokens mesmo — chunk gigante é pior que corte no meio da frase.
        if (ultimaFronteira > inicio) fim = ultimaFronteira;
        if (fim === inicio) fim = inicio + 1; // bloco único maior que o máximo

        const usados = blocos.slice(inicio, fim);
        chunks.push({
          ordem: ordem++,
          paginaIni: usados[0].pagina,
          paginaFim: usados.at(-1)!.pagina,
          texto: usados.map((b) => b.texto).join("\n"),
          tokens: usados.reduce((soma, b) => soma + b.tokens, 0),
          visibilidade: faixa.visibilidade,
          secao: usados[0].secao,
        });

        if (fim >= blocos.length) break;

        // Sobreposição: volta ~15% dos tokens do chunk que acabou de fechar.
        // Ela nunca sai da faixa, porque o laço inteiro é interno à faixa — é
        // assim que a regra "chunk não atravessa visibilidade" se sustenta mesmo
        // com sobreposição.
        const alvo =
          fim - inicio > 1
            ? tokensDeSobreposicao(usados, opcoes.sobreposicao)
            : 0;
        let recuo = 0;
        let acumulado = 0;
        while (recuo < usados.length - 1 && acumulado < alvo) {
          acumulado += usados[usados.length - 1 - recuo].tokens;
          recuo += 1;
        }
        inicio = fim - recuo;
      }
    }
  }

  return chunks;
}

/**
 * Corta a faixa em grupos, um por capítulo/seção — fronteira dura, como a de
 * visibilidade.
 *
 * Sem isto, um chunk que começa no Cap. V e termina no Cap. VII carrega o rótulo
 * do capítulo onde COMEÇOU e cita o texto de outro. Num documento que reinicia a
 * numeração de artigo a cada capítulo, isso não é imprecisão: é citação errada,
 * apontando para um artigo que existe e diz outra coisa. O preço é ter capítulos
 * curtos virando chunks curtos, e é um preço bom.
 */
function porSecao(blocos: readonly Bloco[]): Bloco[][] {
  const grupos: Bloco[][] = [];
  let atual: Bloco[] = [];
  for (const bloco of blocos) {
    if (ehTituloDeSecao(bloco.texto) && atual.length > 0) {
      grupos.push(atual);
      atual = [];
    }
    atual.push(bloco);
  }
  if (atual.length > 0) grupos.push(atual);
  return grupos;
}

function tokensDeSobreposicao(
  blocos: readonly Bloco[],
  fracao: number,
): number {
  return Math.floor(blocos.reduce((soma, b) => soma + b.tokens, 0) * fracao);
}
