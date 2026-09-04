---
name: condominio-plano-de-contas
description: Plano de contas de condomínio residencial brasileiro em três níveis (grupo/subgrupo/conta) com regras de classificação ordinário-extraordinário e fundo, critérios de rateio, sinônimos de balancete de administradora e travas de consistência contábil; use ao importar balancete, classificar lançamento ou construir o motor de alertas financeiro do Breeze.
---

# Plano de contas — condomínio residencial

Este plano é o **padrão de partida** do Breeze. Ele existe para dar um ponto de largada à
importação assistida do balancete (SPEC §5.1) e ao motor de alertas (SPEC §5.3) — não para
substituir o plano real da administradora. Ver seção "Alerta de espelhamento" no fim: divergir
do plano da administradora é o erro mais caro que este produto pode cometer.

## 1. Estrutura de código

Três níveis, código numérico `G.SS.CC`: **grupo** (1 dígito), **subgrupo** (2 dígitos dentro do
grupo), **conta** (2 dígitos dentro do subgrupo). Exemplo: `2.02.01` = grupo 2 (Despesas),
subgrupo 02 (Administração), conta 01 (Taxa de administração). A árvore vive na tabela `contas`
(SPEC §2, `conta_pai_id`) — o código aqui é convenção de exibição, não a chave primária.

## 2. Receitas (grupo 1)

**1.1 Receitas ordinárias**
- 1.1.01 Taxa condominial ordinária
- 1.1.02 Taxa condominial — unidades não residenciais/comerciais (se houver)

**1.2 Receitas extraordinárias**
- 1.2.01 Taxa extraordinária — rateio de obra específica
- 1.2.02 Taxa extraordinária — reposição de fundo

**1.3 Fundo de reserva**
- 1.3.01 Contribuição mensal ao fundo de reserva
- 1.3.02 Rendimento de aplicação do fundo de reserva

**1.4 Fundo de obras** (quando segregado do fundo de reserva)
- 1.4.01 Contribuição mensal ao fundo de obras
- 1.4.02 Rendimento de aplicação do fundo de obras

**1.5 Multas e juros**
- 1.5.01 Multa por atraso de taxa condominial
- 1.5.02 Juros de mora
- 1.5.03 Multa por infração ao regimento interno

**1.6 Rendimento de aplicação — conta corrente**
- 1.6.01 Rendimento de conta corrente/poupança operacional

**1.7 Uso de área comum**
- 1.7.01 Locação de salão de festas
- 1.7.02 Locação de vaga de garagem
- 1.7.03 Locação de espaço para antena/publicidade/comércio

**1.8 Outras receitas**
- 1.8.01 Reembolso de sinistro (seguro)
- 1.8.02 Venda de material/sucata/bens inservíveis
- 1.8.03 Receitas diversas não classificadas — usar como exceção, nunca como padrão

## 3. Despesas (grupo 2)

**2.1 Pessoal e encargos**
- 2.1.01 Salários — equipe própria (zelador, porteiro, faxineira, jardineiro)
- 2.1.02 13º salário
- 2.1.03 Férias e 1/3 constitucional
- 2.1.04 FGTS
- 2.1.05 INSS patronal
- 2.1.06 Rescisões e verbas trabalhistas
- 2.1.07 Vale-transporte / vale-refeição / cesta básica
- 2.1.08 Exames ocupacionais (ASO) e medicina do trabalho
- 2.1.09 Uniformes e EPI

**2.2 Administração**
- 2.2.01 Taxa de administração (honorários da administradora)
- 2.2.02 Assessoria contábil
- 2.2.03 Assessoria jurídica preventiva/consultiva
- 2.2.04 Material de escritório e expediente
- 2.2.05 Correios, cartório e reconhecimento de firma
- 2.2.06 Tarifas e despesas bancárias
- 2.2.07 Software/sistema de gestão condominial

**2.3 Manutenção predial**
- 2.3.01 Manutenção hidráulica
- 2.3.02 Manutenção elétrica
- 2.3.03 Pintura e reparos gerais
- 2.3.04 Manutenção de esquadrias e portões
- 2.3.05 Dedetização e controle de pragas
- 2.3.06 Manutenção de bombas e pressurizadores
- 2.3.07 Limpeza de caixa d'água/cisterna
- 2.3.08 Jardinagem e paisagismo
- 2.3.09 Manutenção de piscina

**2.4 Elevadores**
- 2.4.01 Manutenção mensal (contrato fixo)
- 2.4.02 Peças e reparos avulsos
- 2.4.03 Modernização/adequação normativa [VERIFICAR — enquadramento como despesa corrente vs.
  capital costuma depender do valor e da vida útil agregada; confirmar critério contábil com a
  administradora]

**2.5 Limpeza e conservação**
- 2.5.01 Material de limpeza
- 2.5.02 Serviço terceirizado de limpeza
- 2.5.03 Coleta de lixo especial/reciclagem

**2.6 Segurança e portaria**
- 2.6.01 Empresa de portaria/vigilância terceirizada
- 2.6.02 Monitoramento e manutenção de CFTV
- 2.6.03 Manutenção de interfone/cerca elétrica/alarme
- 2.6.04 Central de monitoramento remoto

**2.7 Água, energia e gás**
- 2.7.01 Água e esgoto — áreas comuns
- 2.7.02 Energia elétrica — áreas comuns
- 2.7.03 Gás (GLP/GN) — áreas comuns

**2.8 Seguros**
- 2.8.01 Seguro predial obrigatório (incêndio — art. 13, Lei 4.591/1964) [VERIFICAR referência
  legal exata]
- 2.8.02 Seguro de responsabilidade civil
- 2.8.03 Seguro de vida da equipe (quando cláusula de CCT exigir) [VERIFICAR]

**2.9 Jurídico**
- 2.9.01 Honorários advocatícios — ações judiciais
- 2.9.02 Custas e despesas processuais
- 2.9.03 Consultoria jurídica avulsa (fora do contrato de assessoria)

**2.10 Obras e melhorias**
- 2.10.01 Obra de reforma estrutural
- 2.10.02 Obra de acessibilidade
- 2.10.03 Modernização de fachada/áreas comuns
- 2.10.04 Projetos técnicos e ART/RRT

**2.11 Taxas e tributos**
- 2.11.01 Taxas municipais (alvará, licença de funcionamento)
- 2.11.02 IPTU de área comum, quando incidente [VERIFICAR — regra varia por convenção e
  município]
- 2.11.03 Multas administrativas não trabalhistas

## 4. Regras de classificação

**Ordinário vs. extraordinário.** Ordinária é a taxa que cobre o custeio previsível e recorrente
do orçamento aprovado em assembleia (grupo 2 inteiro, exceto obras pontuais). Extraordinária é
a taxa cobrada para um fim específico e não recorrente, tipicamente uma obra ou reposição de
fundo deficitário — deve ter deliberação de assembleia vinculada (`deliberacoes.chunk_id`) que
autorize valor, prazo e destinação. Lançamento em conta 1.2.x sem deliberação vinculada é
inconsistência a sinalizar, não a bloquear silenciosamente.

**Fundo de reserva vs. fundo de obras vs. custeio.** Fundo de reserva cobre emergência e
manutenção extraordinária de curto prazo (ex.: bomba queimada). Fundo de obras — quando o
condomínio o segrega — financia obra planejada e orçada. Custeio corrente (grupo 2) cobre
despesa recorrente do mês. **Regra dura:** débito em conta de fundo de reserva ou de obras exige
`deliberacao_id`; débito sem ata é o alerta "Fundo de reserva sem ata" (SPEC §5.3, severidade
crítica) — é a inconsistência mais citada como dor no briefing (item 4). Aporte ao fundo vindo
da taxa ordinária mensal é normal; o que exige ata é a *saída*, não a *entrada*.

**Despesa de capital (obra) vs. despesa corrente.** Corrente é o que mantém o existente
funcionando dentro do padrão atual (manutenção, reparo, substituição como-está). Capital é o que
cria, amplia ou eleva o padrão do bem (reforma estrutural, modernização, obra de acessibilidade)
— grupo 2.10. Critério prático: se o valor está no orçamento recorrente aprovado e se repete
todo ano, é corrente; se depende de aprovação específica de assembleia com fonte de custeio
própria (rateio extraordinário ou fundo), é capital. [VERIFICAR — o critério contábil formal
(capitalização e depreciação) normalmente não se aplica a condomínio, que apura por regime de
caixa; confirmar se a administradora usa caixa ou competência antes de aplicar esta regra]

## 5. Critérios de rateio

**Fração ideal** — proporcional à fração ideal da unidade (SPEC `unidades.fracao_ideal`). Usa-se
para: taxa condominial ordinária (regra geral do art. 1.336, I, CC, salvo convenção em
contrário) [VERIFICAR], fundo de reserva, fundo de obras, seguro predial obrigatório, taxa
extraordinária de obra que beneficia a todos proporcionalmente.

**Rateio igualitário** — valor dividido por número de unidades, independente da fração ideal.
Usa-se para: taxas que a convenção define como benefício igual per capita (ex.: manutenção de
elevador quando a convenção assim dispuser, portaria/segurança em alguns condomínios) — **isso
varia por convenção e nunca deve ser assumido por padrão**; o rateio de cada rubrica é o que a
convenção do condomínio específico determina, não uma regra geral de mercado. Sempre conferir a
convenção antes de classificar automaticamente.

**Rateio por uso** — quando a despesa é vinculada a um recurso opcional (vaga extra, área
comum locável), o custo é do usuário, não rateado.

## 6. Sinônimos e variações de nomenclatura em balancete de administradora

Administradoras usam vocabulário próprio, quase nunca alinhado ao plano acima. Reconhecimento de
texto deve mapear por sinônimo, não por igualdade de string:

| Termo na conta 2.2.01 (taxa de administração) | Termo na conta 2.1.01 (salários) | Termo na conta 2.6.01 (portaria) |
|---|---|---|
| "taxa de adm", "honorários administração", "adm. condominial", "taxa administrativa", "gestão condominial" | "folha de pagamento", "salários e ordenados", "mão de obra própria" | "vigilância", "segurança patrimonial", "portaria terceirizada" |

Outros pares frequentes: "fundo de reserva" ≈ "FR" ≈ "reserva técnica"; "conservação" ≈
"manutenção geral" ≈ "reparos diversos"; "água e esgoto" ≈ "SABESP/concessionária" (nome do
fornecedor local substitui o nome da conta); "seguro obrigatório" ≈ "seguro predial" ≈ "seguro
incêndio/responsabilidade civil"; "material de limpeza" ≈ "material de consumo" (ambíguo — pode
misturar limpeza e escritório, exige conferência humana). A tela de conferência lado a lado
(SPEC §5.1) existe justamente para esse tipo de ambiguidade — o classificador propõe, nunca
publica sozinho.

## 7. Regras de consistência (travas de publicação)

Direto do SPEC §5.1, item 3 — implementadas como bloqueio, não aviso:

1. **Soma das contas = total do subgrupo = total do grupo.** Cada nível soma exatamente os
   filhos; divergência de centavo bloqueia.
2. **Receitas − despesas = variação de saldo declarada no balancete.** Se a administradora
   declara um delta que não bate com receitas menos despesas do período, é inconsistência.
3. **Saldo final do mês = saldo inicial do mês seguinte.** Corrente de caixa contínua; quebra
   de corrente indica balancete faltando ou lançamento fora de competência.

Essas três travas rodam antes de qualquer publicação e usam `valor_centavos` em `bigint` — nunca
float (SPEC §2), para evitar erro de arredondamento mascarar uma inconsistência real.

## 8. Alerta de espelhamento — não normalizar o plano da administradora

Este plano de contas é **esqueleto de referência**, não o plano final de nenhum condomínio real.
Cada condomínio deve ter seu plano mapeado 1:1 contra o que a administradora já usa no
balancete que envia todo mês. **Nunca "corrigir" ou renomear a estrutura da administradora para
parecer mais organizada** — o efeito colateral é destruir a comparabilidade histórica: um gráfico
de série temporal que muda de plano no meio do caminho vira gráfico de duas séries incompatíveis
coladas, e ninguém percebe até o número parecer errado. Se a administradora reclassifica ou
renomeia uma conta, o Breeze registra a mudança como evento de migração de plano, não como edição
silenciosa — e o histórico anterior permanece rotulado com o plano vigente à época.
