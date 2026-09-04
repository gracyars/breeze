---
name: ocr-documento-fiscal-br
description: Engenharia de extração de documento fiscal/contábil brasileiro para o Breeze — decisão nativo-vs-OCR, armadilhas de layout (balancete, NF-e/DANFE, boleto), erros sistemáticos de dígito, parsing de número BR e travas de consistência antes de publicar.
---

# OCR de documento fiscal brasileiro

Serve `eng-ingestao` e `curador-acervo`. Regra de fundo (SPEC §5.1, D1): **extração propõe,
humano confere lado a lado com o PDF, travas de consistência bloqueiam publicação divergente.**
Nada aqui automatiza confiança — existe para tornar a conferência rápida e saber quando não
confiar em nada.

## 1. Heurística nativo vs. OCR

Não decidir por "tem camada de texto → usa nativo". Decidir por qualidade do texto extraído:

1. Extrai texto nativo da página, se houver camada.
2. Mede **taxa de gibberish**: proporção de tokens que não são palavra de dicionário PT-BR nem
   número nem pontuação válida, densidade de caractere de substituição (`�`), proporção de
   linhas com comprimento anômalo frente à média da página. Limiares de partida (calibrar com
   amostra real antes de fechar):
   - gibberish > ~15% dos tokens → texto nativo não confiável, mesmo existindo.
   - menos de ~20 caracteres numa página com conteúdo visual claro → nativo ausente na prática,
     forçar OCR.
   - blocos de números sem separador/alinhamento coerente (colunas "coladas") → suspeitar mesmo
     com gibberish baixo.
3. Se nativo reprova, roda OCR e compara `confianca_ocr` contra o nativo. **O maior risco não é
   ausência de camada de texto — é camada de texto ruim de scan antigo já OCRizado por outro
   sistema**: atas antigas costumam já ter passado por OCR de baixa qualidade e carregam esse
   texto como se fosse nativo. Rodar OCR de novo nessas páginas quase sempre supera o texto
   herdado — a heurística nunca pode parar em "existe camada, logo confio", precisa medir a
   qualidade dela.
4. Página de baixa confiança nos dois caminhos vira candidata a digitação manual do trecho
   crítico, sinalizada ao `curador-acervo` — não publicar número sem passar em nenhum dos dois.

## 2. Layouts brasileiros e armadilhas

- **Balancete de administradora** — o mais perigoso. Tabela multi-coluna (conta | histórico |
  débito | crédito | saldo), fonte pequena, grade fraca ou ausente. Armadilhas: totalizador de
  subgrupo com formatação quase idêntica a linha normal (só negrito ou traço acima — fácil de
  perder no OCR); nome da conta-pai como cabeçalho de seção em vez de coluna — tratado como
  linha vira lançamento fantasma; colunas débito/crédito próximas o bastante para o OCR trocar
  de coluna quando a tabela desalinha por poucos pixels.
- **NF-e / NFS-e e DANFE** — DANFE tem layout semi-padronizado (chave de acesso de 44 dígitos
  em código de barras + texto, CNPJ do emitente, valor total, tributos destacados); NFS-e varia
  por prefeitura, sem leiaute nacional único. Nunca assumir posição fixa entre municípios —
  ancorar por rótulo textual ("Valor Total da Nota", "CNPJ/CPF Tomador"), não por coordenada.
- **Recibo simples** — estrutura mínima, redação livre. Valor por extenso, quando presente, é a
  melhor checagem cruzada contra o valor numérico.
- **Boleto** — a **linha digitável** tem dígito verificador por campo (módulo 10/11 conforme o
  bloco): a única checagem que independe de OCR externo. Se o dígito verificador não fecha, a
  linha foi lida errado — sem precisar de humano para saber, mas ainda precisando dele para
  corrigir.

## 3. Erros sistemáticos de dígito — valor monetário nunca vem direto do OCR

Confusões recorrentes de fonte/scan, não ruído aleatório: **8↔3, 5↔6, 0↔O, 1↔7** (e, com serifa
fraca ou baixa resolução, 1↔l↔I). São sistemáticas porque nascem de semelhança de traço — por
isso **não se resolvem rodando o OCR de novo** nem com "confiança média" aceitável: um valor com
um dígito trocado passa qualquer teste de formato (ainda parece centavo válido) e só é pego por
conferência humana contra o PDF ou por trava de soma (seção 6). Por isso, **nenhum
`valor_centavos` é gravado em `lancamentos` a partir de OCR sem confirmação humana** — confiança
alta por caractere não captura esse erro, porque o caractere errado geralmente também tem alta
confiança individual (o OCR "tem certeza" do 8 que na verdade é um 3 mal impresso).

## 4. Parsing de número brasileiro

Formato BR: ponto como milhar, vírgula como decimal — inverso do formato US.

- Remover `.` de milhar antes de trocar `,` por `.` decimal — nunca o inverso (trocaria o
  separador decimal certo junto com os de milhar).
- `R$` e espaços (incluindo NBSP, comum em PDF exportado) são removidos antes do parse, nunca
  comparados como parte do valor.
- **Parênteses ou `-`** indicam negativo — comum em balancete para despesa/estorno: `(1.234,56)`
  e `1.234,56-` são ambos `-123456` centavos. Se o layout usa coluna separada de débito/crédito
  em vez de sinal, o sinal é inferido pela coluna, não pelo texto.
- Todo valor vira **centavos como inteiro (bigint)** no parse, nunca float em etapa
  intermediária — float acumula erro de arredondamento inaceitável em contabilidade, e o modelo
  de dados exige bigint (SPEC §2). Rejeitar (não arredondar) qualquer string com mais de 2 casas
  decimais — indica erro de leitura, não centavo real.

## 5. Extração de tabela de balancete: coordenada vs. linha de texto

Usar as duas estratégias e cruzar:

- **Por coordenada** — agrupa tokens por posição X/Y em célula de grade inferida. Robusta com
  grade visível/alinhamento consistente; frágil com scan torto (skew) ou largura de coluna
  variável entre páginas.
- **Por linha de texto (reading order)** — usa ordem de leitura do OCR e separadores (espaços
  múltiplos, tabulação inferida). Robusta a leve rotação; frágil quando duas colunas próximas
  (débito/crédito lado a lado) viram uma só coluna aos olhos do OCR.
- **Detecção de coluna**: usar a distribuição de posições X de tokens numéricos na página
  inteira, não só na linha — colunas reais formam clusters estáveis ao longo de muitas linhas;
  valor fora do cluster é candidato a erro de coluna.
- **Reconhecimento de linha de total**: combinar (a) rótulo textual ("total", "subtotal",
  "saldo") normalizado sem acento/caixa; (b) formatação destacada quando extraível; (c) checagem
  aritmética — o valor candidato bate com a soma das linhas do grupo desde o último total? Essa
  checagem é o sinal mais confiável e alimenta a mesma trava da seção 6 — não é trabalho
  duplicado.

## 6. Score de confiança por campo/página e tela de conferência (§5.1)

- **Por campo**: combinar confiança nativa do motor com sinais próprios — o valor bateu em duas
  estratégias de extração? valor por extenso confere? dígito verificador (boleto) fechou? Cada
  "sim" sobe o score; divergência entre estratégias derruba o score mesmo com alta confiança
  isolada por caractere.
- **Por página**: agregado dos campos, penalizado por skew detectado, DPI estimado abaixo de
  ~200, e proporção de campos não reconhecidos.
- A tela de conferência lado a lado (PDF à esquerda com região destacada, linha editável à
  direita — SPEC §5.1) usa o score para **ordenar** o que o humano revisa primeiro e
  **destacar** campo de baixa confiança — nunca para decidir sozinha o que publicar. Score baixo
  direciona atenção; quem bloqueia publicação são as travas da seção 7.

## 7. Travas de consistência antes de publicar

Direto do SPEC §5.1 — divergência bloqueia publicação, sem exceção manual silenciosa:

1. Soma das contas de um subgrupo = total do subgrupo declarado.
2. Total de receitas − total de despesas = variação de saldo declarada no período.
3. Saldo final do mês anterior = saldo inicial do mês corrente (encadeamento entre balancetes
   consecutivos — pega erro que parece plausível isolado mas quebra a série).
4. Todo lançamento proposto carrega `documento_id` + `pagina_origem` antes de ser confirmável —
   sem página de origem, não é publicável ("sem fonte, não existe").

Essas travas rodam depois da edição humana na tela de conferência, não só na extração
automática — humano também erra dígito ao digitar; a trava vale para o valor final, não para o
bruto do OCR.

## 8. Escolha de motor de OCR

Critérios de avaliação, em ordem de peso para este domínio:

1. **Acurácia em tabela densa com fonte pequena em português** — testar com amostra real de
   balancete escaneado, não recibo simples; motor bom em documento genérico pode ser mediano em
   tabela financeira.
2. **Exposição de confiança por caractere/campo**, não só por página — sem isso a seção 6 não
   funciona.
3. **Custo por página** em volume mensal esperado e previsibilidade (evitar tarifação que
   penalize desproporcionalmente página grande/multi-coluna).
4. **Latência aceitável** para o fluxo assíncrono de ingestão (SPEC §3) — não precisa tempo
   real, precisa ser previsível.
5. Suporte a reprocessamento idempotente por `sha256` sem custo duplicado (cache por hash de
   página, quando o fornecedor permitir).

**Teste mínimo antes de fechar fornecedor**: rodar o candidato contra 5–10 páginas reais de
balancete + 2–3 DANFE/NFS-e + 2 boletos do próprio acervo, medir erro de dígito por comparação
manual campo a campo contra o PDF, confirmar que a saída inclui confiança por campo. Reprovar
fornecedor sem confiança por campo mesmo com boa acurácia média — a arquitetura depende desse
sinal para a tela de conferência, não só do resultado final.
