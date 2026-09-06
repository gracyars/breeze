import { describe, expect, it } from "vitest";

import {
  normalizaMarcadores,
  normalizaUnidadeDeArea,
} from "@/lib/ocr/marcadores";

/**
 * Os casos abaixo são reais: saíram do OCR da Convenção registrada
 * (`docs/ocr/medicao-vision-convencao.md`), não de exemplo inventado. A página 12,
 * que descreve o quórum de instalação e de deliberação, é a que mais importa —
 * é o tipo de trecho que o morador vai citar numa assembleia.
 */
describe("normalizaMarcadores", () => {
  it("conserta o romano que o OCR troca por letra", () => {
    const linhas = [
      "i. Apreciar e deliberar sobre a prestação de contas do Síndico.",
      "il. Fixar o orçamento anual para o exercício social vincendo.",
      "li. Eleger o Síndico, Subsíndico e os membros do Conselho Consultivo.",
      "iv. Impor multa a condômino.",
    ];
    const saida = normalizaMarcadores(linhas);

    expect(saida.map((l) => l.marcador)).toEqual(["i", "ii", "iii", "iv"]);
    expect(saida.map((l) => l.corrigido)).toEqual([false, true, true, false]);
    expect(saida[1].texto).toBe(
      "ii. Fixar o orçamento anual para o exercício social vincendo.",
    );
    // O corpo do texto sai intocado — quem confere compara com o PDF sem ruído nosso.
    expect(saida[2].texto.endsWith("Conselho Consultivo.")).toBe(true);
  });

  it("conserta a letra que o OCR troca por dígito", () => {
    const saida = normalizaMarcadores([
      "m) A Assembleia Geral Ordinária deverá ser realizada até o final do trimestre.",
      "n) A Assembleia Geral Extraordinária decidirá, entre outros itens, sobre:",
      "0) Para instalação da Assembleia Geral será observado o seguinte quórum:",
      "p) Para deliberação em Assembleia Geral deverá ser obedecido o seguinte quórum:",
    ]);

    expect(saida.map((l) => l.marcador)).toEqual(["m", "n", "o", "p"]);
    expect(saida[2].corrigido).toBe(true);
    expect(saida[2].texto.startsWith("o) Para instalação")).toBe(true);
  });

  it("rebaixa a maiúscula espúria do reconhecedor", () => {
    const saida = normalizaMarcadores(["j) primeiro", "K) segundo"]);
    expect(saida[1].marcador).toBe("k");
    expect(saida[1].corrigido).toBe(true);
  });

  it("marca a lacuna em vez de adivinhar o marcador perdido", () => {
    const saida = normalizaMarcadores([
      "i. primeiro subitem",
      "ii. segundo subitem",
      "Destituição do Síndico, sem necessidade de motivação para essa decisão.",
      "iv. Substituição da Administradora ou restrição de suas funções.",
    ]);

    // A linha do meio perdeu o `iii.` no OCR. O módulo não inventa o marcador —
    // sinaliza, porque inventar item de convenção é pior que faltar.
    expect(saida[2].marcador).toBeUndefined();
    expect(saida[3].suspeita).toBe("marcador_ausente");
    expect(saida[3].corrigido).toBe(false);
  });

  it("não renumera a lista em cascata depois de um marcador perdido", () => {
    // Regressão de um erro real: na página 8 da Convenção o OCR perdeu o `xi.`,
    // e a versão anterior deste módulo passou a "corrigir" para trás todos os
    // itens seguintes — `xvi.` virava `xv.`, `xvii.` virava `xvi.` — corrompendo
    // a numeração de uma convenção inteira a partir de um item não lido.
    const saida = normalizaMarcadores([
      "xiv. Manter em dia o pagamento dos tributos.",
      "Proceder ao registro de todos os empregados do CONDOMÍNIO.",
      "xvi. Emitir e enviar os boletos de cobrança aos condôminos.",
      "xvii. Pagar pontualmente as taxas de serviços públicos.",
    ]);

    expect(saida.map((l) => l.marcador)).toEqual([
      "xiv",
      undefined,
      "xvi",
      "xvii",
    ]);
    expect(saida.some((l) => l.corrigido)).toBe(false);
    expect(saida[2].suspeita).toBe("marcador_ausente");
  });

  it("sinaliza o marcador que repete o anterior em vez de reescrevê-lo", () => {
    // Página 14 da Convenção, conferida contra a imagem da página: o `iii.` do
    // fundo de reserva chega como `ii.`, repetindo o item acima. Reescrever
    // renumeraria o resto da lista; ficar calado esconderia a linha da
    // conferência. O certo é o meio-termo: preserva e sinaliza.
    const saida = normalizaMarcadores([
      "i. 5% (cinco por cento) da contribuição mensal de cada condômino.",
      "ii. Juros moratórios e multas previstas nesta Convenção.",
      "ii. 20% (vinte por cento) do saldo verificado no orçamento.",
      "iv. Rendimentos decorrentes da aplicação das verbas do fundo de reserva.",
    ]);

    expect(saida[2].corrigido).toBe(false);
    expect(saida[2].texto).toBe(
      "ii. 20% (vinte por cento) do saldo verificado no orçamento.",
    );
    expect(saida[2].suspeita).toBe("marcador_fora_de_sequencia");
  });

  it("não confunde título em maiúscula com subitem em minúscula", () => {
    // Outro erro real: "VI. ADMINISTRAÇÃO DO CONDOMÍNIO" é título de capítulo e
    // virava "ii. ADMINISTRAÇÃO DO CONDOMÍNIO" ao ser absorvido pela lista de
    // subitens aberta logo acima. Caixa é nível hierárquico, não estilo.
    const saida = normalizaMarcadores([
      "i. Convocar a Assembleia Geral.",
      "VI. ADMINISTRAÇÃO DO CONDOMÍNIO",
    ]);
    expect(saida[1].texto).toBe("VI. ADMINISTRAÇÃO DO CONDOMÍNIO");
    expect(saida[1].corrigido).toBe(false);
  });

  it("não reescreve reinício de lista", () => {
    // `i.` depois de `ii.` é começo de nova lista com pelo menos a mesma
    // probabilidade de ser leitura errada de `iii.` — e reescrever empurraria
    // toda a numeração seguinte.
    const saida = normalizaMarcadores([
      "i. primeiro subitem da cláusula anterior",
      "ii. segundo subitem da cláusula anterior",
      "i. primeiro subitem da cláusula nova",
    ]);
    expect(saida[2].marcador).toBe("i");
    expect(saida[2].corrigido).toBe(false);
  });

  it("não mexe em lista numérica legítima", () => {
    const saida = normalizaMarcadores([
      "8) oitava cláusula",
      "9) nona cláusula",
      "10) décima cláusula",
    ]);
    expect(saida.every((l) => !l.corrigido)).toBe(true);
    expect(saida.map((l) => l.familia)).toEqual([
      "arabico",
      "arabico",
      "arabico",
    ]);
  });

  it("preserva linha de texto corrido", () => {
    const linha =
      "O CONDOMÍNIO rege-se pelas disposições da Lei Federal nº 4.591, de 16 de dezembro de 1964.";
    const [saida] = normalizaMarcadores([linha]);
    expect(saida.texto).toBe(linha);
    expect(saida.marcador).toBeUndefined();
    expect(saida.corrigido).toBe(false);
  });

  it("guarda o texto original mesmo quando corrige", () => {
    const saida = normalizaMarcadores(["i. um", "il. dois"]);
    expect(saida[1].textoOriginal).toBe("il. dois");
    expect(saida[1].texto).toBe("ii. dois");
  });
});

describe("normalizaUnidadeDeArea", () => {
  it("restaura o expoente depois de número", () => {
    expect(
      normalizaUnidadeDeArea(
        "a área privativa de 49,68 m?, a área comum de 10,23 m2",
      ),
    ).toBe("a área privativa de 49,68 m², a área comum de 10,23 m²");
  });

  it("não reescreve interrogação legítima", () => {
    expect(normalizaUnidadeDeArea("quantos m? a unidade tem?")).toBe(
      "quantos m? a unidade tem?",
    );
  });
});
