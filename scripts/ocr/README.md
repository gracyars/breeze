# OCR local — Apple Vision

`vision_ocr.swift` roda OCR **offline**, na própria máquina, usando o framework Vision do macOS.
Nenhuma página sai daqui: não há chamada de rede, não há fornecedor, não há contrato de operador
LGPD a firmar para usar isto. Custo zero.

```sh
swift scripts/ocr/vision_ocr.swift "<arquivo.pdf>" <dir-saida> [dpi]
# padrão: 300 DPI
```

Saída, um arquivo por página + `resumo.json`:

```json
{ "pagina": 12, "dpi": 300, "linhas": 47, "confianca_media": 0.98, "confianca_min": 0.5,
  "caracteres": 3279, "texto": "…", "linhas_detalhe": [ { "texto": "…", "confianca": 0.99, "y": 0.31, "x": 0.5 } ] }
```

`confianca_media` e `confianca_min` alimentam `documento_paginas.confianca_ocr`; `linhas_detalhe`
existe para a tela de conferência conseguir destacar **a linha** de baixa confiança, não a página
inteira.

## Por que Vision e não a API paga do ADR-0006

O ADR-0006 escolheu OCR por API paga partindo de uma premissa que o acervo real desmentiu: "atas
antigas, scan torto, abaixo de 200 DPI". O inventário (`docs/inventario-acervo.md`) mostrou que
**nenhum documento é anterior a 2025** e que só 2 dos 43 PDFs são escaneados. Medição em
`docs/ocr/medicao-vision-convencao.md`. A revisão do ADR é do `arquiteto`.

## Limites conhecidos — leia antes de confiar na saída

1. **Marcador de lista romano/letra é o erro sistemático.** `ii.` sai como `il.`, `iii.` como
   `li.`, `o)` como `0)`. Numa convenção de condomínio o marcador **é** a unidade de citação
   ("item ii da cláusula p"), então este é o erro que mais importa aqui — mais que qualquer
   palavra errada no corpo do texto. Normalização de sequência (o item depois de `i.` é `ii.`)
   resolve a maioria, e o resto é conferência humana.
2. **`m²` sai como `m?`.** Expoente não é reconhecido.
3. **Acento cai em palavra maiúscula ou em fonte fina** (`Sindico`, `dominio`, `orgãos`). A busca
   não sofre — a configuração `public.pt_br` encadeia `unaccent` (ADR-0005) — mas o trecho literal
   citado na tela sofre.
4. **Layout de pôster embaralha a ordem de leitura.** Em página com mockup, coluna sobreposta ou
   diagrama (ex.: "COMUNICADO FACIAL"), as linhas saem intercaladas. A ordenação por posição
   (topo→base, esquerda→direita) resolve texto corrido, não composição gráfica.
5. **Carimbo e selo viram ruído** — na Convenção, a página 18 produziu `ОСОВАРСО` (caracteres
   cirílicos) a partir de um selo de cartório.

## A regra que não muda

Valor financeiro, fração ideal, percentual de quórum e data **nunca** são aceitos direto do OCR
(SPEC §3.3, §5.1, ADR-0006). Troca de dígito é o modo de falha típico e a Convenção contém
justamente a **fração ideal de cada unidade**, que define rateio. O OCR propõe; a conferência
humana publica.
