---
name: rag-citacao-juridica-ptbr
description: Governa recuperação, citação e síntese sobre documentos condominiais (convenção, regimento, atas, balancetes) no Breeze — formato de citação obrigatório, roteamento de intenção, regras de recusa, grounding estrito e avaliação da busca.
---

# RAG e citação jurídica PT-BR

Use ao implementar, revisar ou avaliar qualquer caminho que leia documentos do condomínio e responda
ao morador, síndico ou conselho.

**O risco que esta skill contém:** uma resposta errada sobre quórum ou sobre uma regra da convenção
leva a uma decisão errada numa assembleia real (SPEC §8, risco 2). Alucinação aqui não é bug de UX,
é dano no mundo. Diante de dúvida entre responder e recusar, **recuse**.

---

## 1. Formato de citação (obrigatório)

Toda afirmação carrega sua citação. Afirmação sem citação **não sai da síntese** — é descartada, não
suavizada com "aparentemente" ou "em geral".

Estrutura de dados — uma citação por afirmação, nunca uma lista de fontes no rodapé:

```ts
type Citacao = {
  chunk_id: string;
  documento_id: string;
  documento_titulo: string;         // "Convenção de Condomínio"
  tipo: 'convencao' | 'regimento' | 'ata' | 'comunicado' | 'balancete' | 'contrato';
  data_documento: string | null;    // ISO; null só se o documento não tem data
  pagina_ini: number;
  pagina_fim: number;
  trecho_literal: string;           // copiado byte-a-byte do chunk, 1–3 frases
  confianca_ocr: number | null;     // da página; < 0.85 exige rótulo de baixa confiança
};

type Afirmacao = { texto: string; citacoes: Citacao[] };  // citacoes.length >= 1
```

Invariantes verificáveis em código, não por prompt:
- `trecho_literal` deve ser substring exata do texto do chunk citado. Se não for, a afirmação é
  descartada e o evento é logado como **citação inválida**.
- `pagina_ini/fim` vêm do chunk (SPEC §3.4), nunca do LLM.
- `afirmacoes.length >= 1` e toda afirmação com `citacoes.length >= 1`, ou a resposta vira recusa.

Na UI: `Convenção de Condomínio · convenção · 12/03/2018 · p. 7` seguido do trecho em bloco citado,
com o termo da busca em negrito e link `abrir na página 7`.

---

## 2. Roteamento de intenção

Classifique antes de recuperar. Quatro classes:

**normativa** — "o que a regra diz". Vai para busca híbrida (BM25 + vetorial, RRF) restrita a
convenção e regimento; atas entram só como fonte secundária de deliberação.
*Ex.:* "posso ter cachorro?", "pode fazer obra no sábado?", "quantos votos precisa pra trocar de
administradora?", "tem multa por barulho depois das 22h?".

**factual-documental** — "o que foi decidido/comunicado, quando". Busca sobre atas, comunicados,
contratos, com faceta de data/assembleia obrigatória.
*Ex.:* "o que ficou decidido na última assembleia?", "quando aprovaram a reforma do hall?",
"quem é o síndico atual?".

**quantitativa-financeira** — qualquer coisa com valor, total, comparação, média, mês, "quanto".
**Roteia para SQL sobre `lancamentos`. Nunca RAG sobre balancete escaneado** (SPEC §4, §5.1). O OCR
troca dígito; valor vindo de texto recuperado é proibido em qualquer circunstância.
*Ex.:* "quanto gastamos com elevador em 2025?", "por que a taxa subiu?", "quanto tem no fundo de
reserva?", "a gente tá gastando mais que ano passado?". Se o dado não está em `lancamentos`, responda
"esse mês ainda não foi conciliado" — não caia para RAG.

**fora-de-escopo** — não é sobre este condomínio ou pede juízo jurídico.
*Ex.:* "posso processar meu vizinho?", "o que diz o Código Civil sobre isso?". Resposta: fora do
acervo + saída humana ("falar com o síndico").

Heurística de roteamento (ordem importa, primeira que casar vence):
1. Regex de valor/quantidade — `quanto`, `total`, `custo`, `gasto`, `valor`, `R$`, `média`,
   `orçamento`, `saldo`, `caixa`, `subiu`, `aumentou`, nome de mês, ano isolado → **financeira**.
2. Marcador temporal/evento — `assembleia`, `ata`, `reunião`, `ficou decidido`, `aprovaram`,
   `comunicado`, `aviso`, data explícita → **factual-documental**.
3. Marcador deôntico — `posso`, `pode`, `é permitido`, `é proibido`, `preciso`, `quórum`, `multa`,
   `obrigado a`, `tem direito` → **normativa**.
4. Nada casa e a busca lexical + vetorial retorna score abaixo do piso → **fora-de-escopo**.

Regra de mistura: pergunta híbrida ("quanto custa a multa por barulho?") divide — a regra vem de RAG
normativo, o valor cobrado vem de `lancamentos` ou do texto **literal** da convenção citado, jamais
de cálculo. Nunca deixe uma classe financeira ser absorvida pela normativa.

---

## 3. Regras de recusa

Recuse — texto padrão: **"Não encontrei isso nos documentos do condomínio."** — quando:
- nenhum chunk passa do piso de score depois do RRF (calibre o piso na avaliação, §7);
- os chunks recuperados são do tipo errado para a intenção (ata para pergunta normativa, por exemplo);
- os chunks tratam do tema mas não respondem à pergunta feita (fala de animais, não de porte do cão);
- os trechos se contradizem entre documentos — mostre os dois trechos e **não** escolha um;
- a página tem `confianca_ocr` baixa e o trecho é ilegível.

**Ausência de resultado ≠ inexistência da regra.** Nunca escreva "a convenção não proíbe",
"não há regra sobre isso", "é permitido porque não está vedado". Escreva o que é verdade sobre a
busca, não sobre o mundo: "não encontrei nos documentos indexados". Toda recusa oferece (a)
reformulação sugerida, (b) filtro por tipo de documento, (c) "falar com o síndico" (SPEC §6.2).

Acervo incompleto é recusa: se a convenção não foi indexada, diga isso em vez de responder pelo
regimento.

---

## 4. Grounding estrito — proibições

1. **Nada de conhecimento geral sobre condomínios.** Sem Lei 4.591, sem Código Civil, sem "o usual é
   2/3". Se não está num chunk recuperado deste condomínio, não existe.
2. **Não parafraseie texto normativo como se fosse o texto.** A síntese pode explicar; o trecho
   citado é sempre a redação original, sem correção, sem modernizar, sem "ou seja". Nunca apresente
   paráfrase entre aspas.
3. **Zero aritmética sobre texto recuperado.** Não somar, subtrair, converter percentual em número
   de votos, ratear, projetar. "1/3 dos condôminos" permanece "1/3" — o sistema não sabe quantas
   unidades há a menos que isso venha de dado estruturado.
4. **Não inferir quórum não escrito.** Quórum só sai se estiver literalmente no trecho. Não deduza de
   analogia com outro artigo, nem de "assembleias semelhantes".
5. **Não fundir trechos de documentos ou datas diferentes** numa afirmação só. Uma afirmação, uma
   fonte coerente; regras conflitantes viram duas afirmações com suas duas citações.
6. **Não normalize valores monetários** em texto — reproduza como está escrito.
7. Disclaimer permanente: **não é interpretação jurídica**.

---

## 5. Prompt template de síntese

```
Você responde perguntas de moradores usando SOMENTE os trechos abaixo, extraídos dos
documentos deste condomínio.

TRECHOS:
{{#each chunks}}
[{{id}}] {{documento_titulo}} ({{tipo}}, {{data_documento}}), página {{pagina_ini}}
"{{texto}}"
{{/each}}

PERGUNTA: {{pergunta}}

REGRAS (violação = resposta inválida):
- Cada afirmação deve citar um [id] acima e conter um trecho literal copiado dele.
- Não use nenhum conhecimento sobre condomínios, leis ou práticas fora destes trechos.
- Não calcule, some, converta ou estime valores, percentuais ou número de votos.
- Não afirme quórum que não esteja escrito literalmente num trecho.
- Não parafraseie dentro de aspas. Aspas = texto copiado.
- Se os trechos não respondem à pergunta, responda apenas: {"recusa": true, "motivo": "..."}.
- Nunca conclua que algo é permitido por ausência de proibição.
- Se dois trechos se contradizem, apresente ambos sem escolher.

SAÍDA (JSON):
{"recusa": false, "afirmacoes": [{"texto": "...", "citacoes": [{"chunk_id": "...",
"trecho_literal": "..."}]}], "observacao": "..."}
```

Valide o JSON contra os invariantes da §1 antes de renderizar. Falha de validação → recusa, não
retry silencioso.

---

## 6. Hierarquia na UI

O trecho original é o resultado **primário**; a síntese é **secundária** — o inverso do padrão de
chatbot (SPEC §4, §6.2). Ordem na tela: card de resposta direta com citação → lista de trechos-fonte
com badge de tipo e data → link "abrir na página X". Fonte e síntese sempre convivem.

Conteúdo gerado é rotulado, sempre e visivelmente: `Resumo gerado por IA · confira o trecho original`.
Trecho literal e texto gerado nunca compartilham o mesmo tratamento tipográfico. Página com
`confianca_ocr` baixa ganha rótulo próprio: `texto extraído com baixa confiança`.

---

## 7. Avaliação (agente `avaliador-busca`)

**Conjunto gold** — 60 a 100 perguntas versionadas no repo, em português de morador, não em jargão.
Composição alvo: ~40% normativa, ~20% factual-documental, ~20% quantitativa-financeira
(para provar o roteamento, não o RAG), ~20% sem resposta no acervo (recusa esperada). Inclua
obrigatoriamente: as 10 perguntas mais prováveis do síndico, casos de quórum, casos de contradição
convenção × regimento, e perguntas com erro de digitação e sem acento.

Rótulo por item: `pergunta`, `classe_esperada`, `documento_esperado`, `pagina_esperada` (lista, quando
a resposta é multi-página), `trecho_esperado`, `recusa_esperada: bool`, `notas`. Rotule a partir do
documento, nunca a partir da saída do sistema.

Métricas reportadas:
- **recall@k da página correta** (k = 3 e 10) — a `pagina_esperada` aparece entre os chunks recuperados.
- **taxa de citação inválida** — `trecho_literal` que não é substring do chunk citado, ou página que
  não bate. Meta: 0. Métrica de segurança, não de qualidade.
- **taxa de recusa correta** — recusou quando `recusa_esperada`.
- **taxa de recusa incorreta** — recusou tendo o documento no acervo (custo de utilidade) e, separada,
  **taxa de resposta indevida** — respondeu quando devia recusar (custo de risco; pese 10×).
- **acurácia de roteamento**, com matriz de confusão. Qualquer financeira classificada como normativa
  é falha bloqueante.

Rode a suíte a cada mudança de chunking, embedding, sinônimos, ranking ou prompt. Regressão em citação
inválida ou em resposta indevida bloqueia o deploy.

---

## 8. Armadilhas de português

- **Acentuação:** a busca depende da config `unaccent` + `portuguese_stem` (SPEC §4). "sindico" tem de
  achar "síndico"; "convencao", "reuniao", "condominio", "area comum" idem. Teste isso no gold set.
- **Numeração de artigo:** `art. 12` / `Art. 12` / `artigo 12` / `artigo décimo segundo` / `Art. 12º`
  / `Artigo XII` são a mesma coisa. Normalize a query em ambas as direções (ordinal por extenso ↔
  algarismo ↔ romano) antes de buscar, e cite sempre a forma literal do documento.
- **Parágrafos e incisos:** `§ 1º`, `parágrafo único`, `inciso II`, `alínea b`. O chunk deve preservar
  o artigo-pai; inciso solto sem o caput é citação enganosa.
- **Valores em formato brasileiro:** `R$ 1.234,56` — ponto é milhar, vírgula é decimal. Parsing ingênuo
  vira 1.23456. Como valor nunca sai de texto recuperado (§4.3), isso é regra de importação
  estruturada, não de RAG; na síntese, reproduza a string original.
- **Datas por extenso em atas:** "aos quinze dias do mês de março de dois mil e vinte e quatro".
  Extraia para `data_documento` ISO na classificação (com confirmação humana, SPEC §3.5) e continue
  exibindo o literal no trecho.
- **Sinônimos de morador:** "taxa"/"cota"/"rateio", "fundo de reserva"/"FR", "prestação de contas"/
  "balancete", "AGE"/"assembleia extraordinária", "garagem"/"vaga". Vivem na tabela `sinonimos` com
  expansão na aplicação — não em dicionário do Postgres.
- **Maiúsculas e OCR:** títulos em caixa alta e carimbos degradam stemming e viram ruído; `pg_trgm`
  cobre erro de digitação em nome próprio, não erro de OCR em dígito.
