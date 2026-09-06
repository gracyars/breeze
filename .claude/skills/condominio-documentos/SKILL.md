---
name: condominio-documentos
description: Taxonomia documental do condomínio residencial brasileiro — periodicidade, produtor, metadados a extrair, busca típica, visibilidade padrão, sinais de reconhecimento automático e prazo de retenção por tipo de documento; use ao classificar upload, indexar acervo ou definir visibilidade no Breeze.
---

# Taxonomia documental do condomínio

Cobre os tipos de documento que compõem o acervo do Breeze (SPEC §2, tabela `documentos`,
coluna `visibilidade`: público / autenticado / conselho / restrito). Regra de fundo (Briefing §7
decisão 1 e Decisão D2): **só convenção e regimento são públicos**; todo o resto — atas,
balancetes, contratos, prestação de contas — fica atrás de login, porque carrega nome e unidade
de pessoas. `conselho` e `restrito` existem para o que, além disso, expõe dado sensível
individualizado (inadimplência nominal, saúde, imagem) **ou dado pessoal de terceiro que não é
condômino** (representante de fornecedor, responsável técnico, funcionário).

**Classifique o artefato, não o assunto.** Um mesmo assunto costuma gerar dois documentos com
visibilidades diferentes — a proposta comercial que o fornecedor emitiu e o comunicado que a
administração mandou aos moradores sobre aquela proposta. Classificar pelo assunto funde os dois e
vaza o mais sensível. Ver §12-bis.

**A visibilidade do documento é o piso (D13/ADR-0019).** Override de página só *amplia*, nunca
restringe: `conselho < restrito < autenticado < publico`. Consequência prática para quem
classifica: **a página mais sensível arrasta o arquivo inteiro para baixo**. Não existe documento
`autenticado` com uma página `conselho`.

Para cada tipo: periodicidade, quem produz, metadados a extrair para a tabela `documentos`/
`documento_paginas`, o que as pessoas buscam dentro dele, e visibilidade padrão.

## 1. Convenção de condomínio
- **Periodicidade:** única, com emendas raras (exige quórum qualificado e registro em cartório).
- **Produz:** incorporadora no registro inicial; alterações por assembleia + registro cartorial.
- **Metadados:** data de registro, cartório, livro/matrícula, número de emendas incorporadas.
- **Busca típica:** fração ideal, regra de rateio, quórum de assembleia, uso de área comum,
  regras de animais/obras/locação.
- **Visibilidade padrão:** público.

## 2. Regimento interno
- **Periodicidade:** revisão eventual, aprovada em AGE.
- **Produz:** assembleia (aprovação), síndico (proposta).
- **Metadados:** data de aprovação, ata de aprovação vinculada, versão/vigência.
- **Busca típica:** horário de silêncio, regras de mudança, uso de salão/piscina, animais,
  multa por infração.
- **Visibilidade padrão:** público.

## 3. Atas de assembleia (AGO/AGE/AGI)
- **Periodicidade:** AGO anual (prestação de contas, orçamento, eleição); AGE sob demanda; AGI
  uma vez, na instalação do condomínio (ver nota abaixo).
- **Produz:** secretário da mesa/síndico, redigida na própria assembleia. Na AGI, tipicamente a
  incorporadora/construtora conduz, porque ainda não há síndico eleito.
- **Metadados:** espécie (AGO/AGE/AGI — vive em `assembleias.tipo`, enum `tipo_assembleia`, **não**
  em `tipos_documento`: o artefato "ata" é um `codigo` só; a espécie jurídica é propriedade da
  assembleia, não do documento — ver `docs/dominio/taxonomia-documental-decisoes.md` §2), data,
  quórum presente, lista de pauta, `deliberacoes` (item, resultado, votos) vinculadas a
  `chunk_id` para citação exata.
- **Busca típica:** "o que foi decidido sobre X", autorização de gasto, resultado de votação,
  eleição de síndico/conselho.
- **Visibilidade padrão:** autenticado — contém nome e unidade de presentes e votantes.
- **AGI — Assembleia Geral de Instalação:** ato que formaliza a instituição do condomínio após a
  entrega (habite-se), tipicamente antes de haver síndico eleito. **O Código Civil não a nomeia**
  (só trata de AGO, art. 1.350, e AGE, art. 1.355) — "AGI" é nome de mercado, com disciplina de
  fundo mais próxima da Lei 4.591/64 (instituição e primeira administração), matéria que
  `condominio-legal` declara **fora do seu escopo atual** (não cobre incorporação). Trate o
  quórum de uma AGI como `[NÃO COBERTO — condominio-legal em construção]`, não como equivalente
  automático ao de uma AGE comum.

## 3-bis. Resumo de assembleia (não oficial)
- **Periodicidade:** um por assembleia, circula **antes** da ata formal — é frequentemente o que
  o morador lê primeiro.
- **Produz:** administradora (comunicação/atendimento), não a mesa da assembleia.
- **Metadados:** `assembleia_id` (nullable — preenchido na conferência humana por proximidade de
  data), `data_assembleia_referida`, `substitui_documento_id` (nullable, aponta para a ata quando
  publicada).
- **Busca típica:** morador perguntando "o que foi decidido" antes de a ata sair.
- **Visibilidade padrão:** autenticado — mesma audiência da ata; o problema deste tipo não é quem
  vê, é **o que pode ser citado como prova de decisão**. `deliberacoes.documento_id` nunca aponta
  para um `resumo_assembleia`, só para `ata_assembleia`. Toda citação de um resumo carrega o selo
  fixo **"Resumo da administração · não é a ata oficial"** — distinto do selo de "resumo gerado
  por IA" da skill `rag-citacao-juridica-ptbr`, porque aqui quem resume é a gestão, não o modelo.
  Quando ata e resumo do mesmo evento estão indexados, a resposta a uma pergunta
  factual-documental prioriza o trecho da ata. Raciocínio completo:
  `docs/dominio/taxonomia-documental-decisoes.md` §3.
- **Sinais de reconhecimento:** "resumo da assembleia", "principais pontos discutidos", ausência
  da fórmula ritual de abertura de ata ("aos [dia] dias do mês de...", "secretariada por"), sem
  lista de presença formal, tom de comunicado/e-mail em vez de registro cartorial.

## 3-ter. Material de apoio de assembleia
- **Periodicidade:** sob demanda, ligado a uma assembleia específica.
- **Produz:** síndico/administradora, para uso durante a reunião (slide, roteiro).
- **Metadados:** `assembleia_id` nullable, data.
- **Busca típica:** baixa — é referência de "o que foi mostrado", útil sobretudo em disputa sobre
  o que a assembleia discutiu.
- **Visibilidade padrão:** autenticado.
- **Sinais de reconhecimento:** formato slide/apresentação, pouco texto corrido por página, título
  "Apresentação Reunião/Assembleia" + data, sem redação de deliberação.

## 4. Editais de convocação
- **Periodicidade:** um por assembleia, antecede a ata em dias (prazo mínimo previsto em
  convenção).
- **Produz:** síndico ou administradora.
- **Metadados:** data da convocação, data/hora/local da assembleia, pauta, quórum de 1ª e 2ª
  chamada.
- **Busca típica:** "quando é a próxima assembleia", pauta do dia.
- **Visibilidade padrão:** autenticado (costuma ser publicado nos murais fisicamente, mas o
  acervo digital segue a regra geral de login para o não-normativo).

## 5. Balancetes mensais
- **Periodicidade:** mensal, defasado em relação ao mês de competência.
- **Produz:** administradora.
- **Metadados:** competência (mês/ano), saldo inicial, saldo final, `documento_id` de origem
  para cada `lancamento` (SPEC §5.1, item 4 — todo lançamento nasce vinculado ao documento e à
  página).
- **Busca típica:** "quanto gastamos com X esse mês", conferência de lançamento com comprovante.
- **Visibilidade padrão:** autenticado; inadimplência nominal dentro do balancete é `conselho`
  (SPEC §5.5).

## 6. Prestação de contas anual
- **Periodicidade:** anual, apresentada na AGO.
- **Produz:** administradora, com parecer do conselho fiscal anexado.
- **Metadados:** exercício, data de aprovação em AGO, parecer vinculado, status
  (aprovada/aprovada com ressalva/rejeitada).
- **Busca típica:** resumo do ano, comparação orçado vs. realizado anual.
- **Visibilidade padrão:** autenticado.

## 7. Previsão orçamentária
- **Periodicidade:** anual, aprovada antes ou na AGO que abre o exercício.
- **Produz:** síndico/administradora, propõe; assembleia aprova.
- **Metadados:** exercício, valor previsto por conta e por mês (`orcamento`, SPEC §2).
- **Busca típica:** valor previsto de uma rubrica, base para o alerta de estouro de orçamento.
- **Visibilidade padrão:** autenticado.

## 8. Contratos de fornecedor
- **Periodicidade:** vigência plurianual, com aditivos e renovações.
- **Produz:** síndico/administradora assina; fornecedor é a contraparte.
- **Metadados:** CNPJ, razão social, vigência, valor mensal, índice de reajuste
  (`fornecedores`/`contratos`, SPEC §2), objeto do contrato.
- **Busca típica:** "quanto pagamos pela portaria", checar se contrato venceu, comparar reajuste
  com índice contratado.
- **Visibilidade padrão:** autenticado; valores de contrato individual de funcionário/prestador
  pessoa física tendem a `conselho` [VERIFICAR — depende de o contrato expor dado de pessoa
  física identificável; contrato com pessoa jurídica genérica pode ficar autenticado].

## 9. Apólices de seguro
- **Periodicidade:** anual (renovação).
- **Produz:** corretora/seguradora, contratado pelo síndico.
- **Metadados:** seguradora, número da apólice, vigência, cobertura, valor do prêmio.
- **Busca típica:** "estamos segurados contra X", prazo de vigência, franquia.
- **Visibilidade padrão:** autenticado.

## 10. Laudos técnicos (AVCB, SPDA, elevador, cisterna, gás)
- **Periodicidade:** varia por laudo — AVCB (Auto de Vistoria do Corpo de Bombeiros) tem
  validade plurianual definida por norma estadual [VERIFICAR — prazo varia por estado]; SPDA
  (para-raios) costuma ser anual [VERIFICAR]; elevador segue NR/norma técnica com inspeção
  periódica [VERIFICAR periodicidade exata]; cisterna, limpeza semestral é prática comum
  [VERIFICAR]; gás, inspeção de vazamento periódica.
- **Produz:** empresa técnica habilitada (engenheiro/técnico responsável, ART/RRT).
- **Metadados:** tipo de laudo, data de emissão, validade, responsável técnico e registro
  (CREA/CFT), resultado (aprovado/reprovado/com pendência).
- **Busca típica:** "o AVCB está válido", "quando vence o laudo do elevador", conformidade
  regulatória — insumo direto para alerta de vencimento (SPEC §5.3, análogo ao alerta de
  contrato vencendo).
- **Visibilidade padrão:** autenticado; resultado "reprovado/pendência crítica" pode justificar
  destaque, mas não deve virar `restrito` — é informação de segurança coletiva, morador precisa
  ver.

## 11. Notificações e multas
- **Periodicidade:** sob demanda, conforme infração.
- **Produz:** síndico/administradora notifica a unidade infratora.
- **Metadados:** unidade notificada, motivo, artigo do regimento infringido, data, valor da
  multa, status (paga/contestada/cancelada).
- **Busca típica:** morador consultando a própria notificação; conselho auditando aplicação
  consistente de regras.
- **Visibilidade padrão:** **restrito** — visível só à unidade notificada, ao `editor` e ao
  `conselho`. Nunca pública nem geral-autenticada: é dado pessoal negativo de um morador
  específico.

## 12. Documentação de obras
- **Periodicidade:** por projeto (não recorrente).
- **Produz:** síndico contrata; engenheiro/arquiteto responsável assina projeto e ART/RRT;
  fornecedores emitem cotações e notas fiscais.
- **Metadados:** projeto vinculado, cotações anexadas (para o alerta de "cotação ausente", SPEC
  §5.3), deliberação de assembleia que autorizou, cronograma, valor total, `documento_id` de
  cada comprovante.
- **Busca típica:** "quanto custou a obra X", "teve cotação comparativa", status de andamento.
- **Visibilidade padrão:** autenticado **para o projeto, cronograma e comprovação de execução**.
  Cotação e proposta comercial **não** seguem este padrão — têm regra própria na §12-bis, e foi
  justamente classificar cotação como "documentação de obras" que produziu a divergência do
  `inventario-acervo.md` (#13 vs. #35–37).

## 12-bis. Cotações e propostas comerciais
Parecer completo: `docs/juridico/pareceres/2026-09-04-visibilidade-cotacoes.md`.

- **Periodicidade:** sob demanda, em bloco — vêm de duas a quatro por decisão de contratação.
- **Produz:** o fornecedor emite a proposta; a administração produz o comunicado/quadro
  comparativo que a resume aos moradores. **São dois artefatos, com visibilidades diferentes.**
- **Metadados:** fornecedor proponente (CNPJ, razão social), objeto, valor proposto, validade da
  proposta, decisão a que se vincula, `lancamento_id` quando já houver despesa.
- **Busca típica:** "teve cotação comparativa", "por que escolheram essa empresa", conferência do
  alerta de cotação ausente.

**R1 — Proposta comercial na íntegra: `conselho`.** Três razões, em ordem de força:
1. A mesma cotação anexada a um lançamento já é `conselho`/`editor` (`lancamento_anexos`,
   SPEC §2). Se, entrando como `documentos`, virasse `autenticado`, a visibilidade do mesmo
   arquivo dependeria de por onde ele foi carregado — isso é acidente, não política.
2. A íntegra carrega, de praxe, nome, CPF, telefone e e-mail do representante, assinatura e
   ART/CREA do responsável técnico: dado pessoal de terceiro que não é condômino, e desnecessário
   à finalidade do morador (LGPD art. 6º, III).
3. Com o piso da D13, a página do CPF arrasta o documento inteiro. Ou desce tudo, ou vaza.

*Não é razão, e não use como base:* "preço de fornecedor é sigiloso". Preço de pessoa jurídica
não é dado pessoal (LGPD art. 5º, I alcança só pessoa natural) e o condomínio não prometeu sigilo.
Restringir por interesse comercial do fornecedor é decisão de produto, não fundamento jurídico.

**R2 — A prova de concorrência chega ao morador como dado estruturado, não como arquivo.** O
alerta "cotação ausente" pressupõe que o condômino verifique que *houve* mais de uma proposta, não
que leia 27 páginas. Morador vê quantidade, razão social do proponente PJ, valor e data, vindos de
`lancamento_anexos`/`fornecedores`. Mesmo desenho da inadimplência: agregado para o morador,
íntegra para a gestão. *Canto:* proponente pessoa física ou MEI — a razão social **é** dado
pessoal; mostrar só contagem e valores.

**R3 — Comunicado ou quadro comparativo da administração: `autenticado`**, se não carregar PII de
pessoa natural nem dado bancário. A finalidade do artefato é informar o morador e ele já foi
distribuído a todos — publicar no acervo não acrescenta exposição. Se carregar, desce a `conselho`.

**R4 — Nunca `publico`** (não é normativa e impessoal) **nem `restrito`** (`restrito` significa
vinculada a uma unidade; cotação não é de ninguém).

**R5 — Visibilidade uniforme; não usar override de página.** Com D13 o override só amplia, e
ampliar páginas de uma proposta `conselho` é custo de curadoria sem benefício — a necessidade do
morador já está atendida por R2 — enquanto cada override é superfície nova de erro.

**R6 — Depois que a assembleia decide, a visibilidade da proposta não muda; muda qual artefato
carrega a informação para o morador.** A proposta vencedora continua `conselho` — a razão de R1
(dado pessoal de terceiro na íntegra) não desaparece por ter sido escolhida — e a perdedora
também, para sempre, como prova de concorrência para auditoria. O que sobe é o **agregado**,
através de dois documentos novos, não da promoção do PDF da cotação: a deliberação que aprova a
contratação (`deliberacoes`, documento_id = a ata, autenticado) e o `contrato` resultante
(`tipos_documento.contrato`, já autenticado por padrão), referenciando o `fornecedor_id`
vencedor. Mesmo padrão de R2, estendido no tempo. O direito individual de inspecionar documento
da administração (STJ REsp 2.050.372, `condominio-legal` §3) segue exercível fora do Breeze,
pedindo o documento específico ao síndico/administradora — o produto não precisa replicar dado
pessoal de terceiro para toda a base autenticada para não fechar esse direito. Raciocínio
completo: `docs/dominio/taxonomia-documental-decisoes.md` §4.

## 13. Atas do conselho fiscal
- **Periodicidade:** conforme reunião do conselho — tipicamente mensal, acompanhando o
  balancete.
- **Produz:** conselho fiscal, redigida por um de seus membros.
- **Metadados:** data, membros presentes, pauta, parecer/deliberação do conselho, período de
  competência a que se refere.
- **Busca típica:** conselho revisitando posição anterior; morador checando se o conselho já
  questionou um gasto.
- **Visibilidade padrão:** `conselho` — é o registro de trabalho do próprio órgão fiscalizador;
  pode subir para autenticado quando o parecer final é formalmente comunicado aos moradores,
  mas a ata de reunião de trabalho em si fica restrita ao órgão. [VERIFICAR — depende de decisão
  do dono do projeto sobre se o parecer tem valor formal perante assembleia, Briefing §7 item 3]

## 14. Comunicado avulso
- **Periodicidade:** sob demanda — é o tipo de maior volume no acervo real (56% dos 43 documentos
  sondados em `docs/inventario-acervo.md`, achado estrutural que motivou este tipo).
- **Produz:** síndico/administradora.
- **Metadados:** data de emissão, remetente, **categoria** (`financeiro | operacional |
  institucional` — faceta de busca, não `codigo` separado), `unidade_destinataria` nullable — se
  preenchida, **força visibilidade `restrito`** (mesma régua de dado individualizado por unidade
  usada em notificação/multa).
- **Busca típica:** esclarecimento de boleto, liberação de espaço comum, mudança de sistema de
  segurança, rateio de item específico (ex.: enxoval), aviso operacional (elevador, portão).
- **Visibilidade padrão:** autenticado.
- **Sinais de reconhecimento:** curto (1–3 páginas), "informamos", "comunicamos aos senhores
  condôminos", assinado pela gestão. **Armadilha real — não classificar aqui se o texto contiver
  data/hora/local de assembleia junto de pauta:** isso é convocação, tipo `edital_convocacao`,
  **mesmo que o título diga "lembrete" ou "aviso"** — "lembrete de assembleia" tem efeito jurídico
  (CC art. 1.354: a assembleia não delibera se todos não forem convocados); "a churrasqueira
  reabriu" não tem. Na dúvida, classifique como `edital_convocacao` — falha para o lado de maior
  efeito jurídico. Raciocínio completo: `docs/dominio/taxonomia-documental-decisoes.md` §1.1.

## 14-bis. Comunicado de governança
- **Periodicidade:** sob demanda, ligado a início/fim de mandato ou mudança de gestão.
- **Produz:** a própria pessoa/entidade que assume ou deixa o cargo, ou a administradora
  anunciando a mudança.
- **Metadados:** `papel_afetado` (`sindico | subsindico | conselho | administradora`), `evento`
  (`posse | renuncia | apresentacao | substituicao`), data efetiva, e o vínculo correto — **atenção
  à D3**: quando o evento é do síndico terceirizado, vincula a `fornecedores.id`
  (`eh_sindico_terceirizado = true`), **nunca** a `papeis.id`, porque D3 estabelece que síndico
  terceirizado não tem papel nem conta; quando é de subsíndica/conselho (pessoa com conta),
  vincula a `papeis.id`.
- **Busca típica:** "quem é o síndico atual", histórico de gestão em caso de disputa sobre má
  administração.
- **Visibilidade padrão:** autenticado.
- **Retenção:** **permanente** — diferente do comunicado genérico (24 meses). É registro de
  mandato, com o mesmo valor evidencial de uma ata em disputa de destituição (CC art. 1.349) e do
  dever de prestar contas (CC art. 1.348, VIII); reter por prazo curto contrariaria a lógica de
  atas e pareceres, que são permanentes pelo mesmo motivo.
- **Sinais de reconhecimento:** "carta de apresentação", "venho comunicar minha renúncia/saída do
  cargo de síndico", "assumo a gestão a partir desta data".

## 15. Documento da construtora / entrega de obra
- **Periodicidade:** um evento só, na entrega do condomínio — irrelevante para condomínio com
  vários anos de operação, central nos primeiros meses (este condomínio tem ~8 meses de vida,
  `docs/inventario-acervo.md`).
- **Produz:** a construtora/incorporadora, não a gestão do condomínio.
- **Metadados:** `subtipo` (`habite_se | manual_proprietario | formulario_garantia`), CNPJ/razão
  social da construtora, `numero_processo` (para habite-se), `vigencia_garantia_meses` nullable
  por item coberto `[VERIFICAR — inferência de prática de mercado a partir do CC art. 618
  (responsabilidade do empreiteiro por solidez e segurança, 5 anos), artigo fora do recorte
  confirmado de condominio-legal, que cobre só arts. 1.331–1.358 e declara não cobrir
  incorporação/empreitada]`.
- **Busca típica:** "como aciono a garantia de X", "o prédio tem habite-se", especificação técnica
  de sistema predial (elevador, hidráulica, elétrica) para comparar com laudo real.
- **Visibilidade padrão:** autenticado. **Não classificar como público** apesar de o conteúdo ser
  em geral impessoal — a regra "só convenção e regimento são públicos" (D2) não é reaberta por
  esta skill; se houver caso de negócio para exceção (ex.: habite-se), é pergunta para
  `juridico-lgpd`, registrada como aberta em
  `docs/dominio/taxonomia-documental-decisoes.md` §5, não decidida aqui.
- **Sinais de reconhecimento:** habite-se — "certificado de conclusão", "processo nº", órgão
  municipal emissor; manual do proprietário — "manual do proprietário", versão "V0x", extenso
  (dezenas de páginas), organizado por sistema predial; formulário de garantia — "assistência
  técnica", "solicitação de garantia", campos em branco, papel timbrado da construtora.

## 16. Demonstrativo de composição de cota
- **Periodicidade:** mensal, com `competencia`.
- **Produz:** administradora.
- **Metadados:** `competencia` (dia 1), `unidade_id` nullable, rubricas presentes (ordinária,
  extraordinária, fundo de reserva, rateio específico).
- **Busca típica:** "de onde vem esse valor da minha cota", "por que a taxa mudou este mês" —
  especialmente relevante em condomínio recém-entregue com renegociação de boleto e rateio de
  enxoval, como o do acervo real.
- **Visibilidade padrão:** autenticado; **`restrito`** se `unidade_id` estiver preenchida (a
  régua de dado individualizado por unidade, mesma de notificação/multa).
- **Retenção:** permanente — mesma régua de balancete/previsão orçamentária, por comparabilidade
  histórica e porque é insumo direto para investigar a divergência do risco 4 do SPEC §8
  (publicado × balancete real). **Não é a mesma família do "comunicado avulso" apesar de também
  vir da administradora**: tem periodicidade e função financeira estrutural que o comunicado
  genérico não tem.
- **Sinais de reconhecimento:** "composição da cota", "demonstrativo de cota condominial", tabela
  rubrica × valor, mês/ano no título.

## Sinais de reconhecimento automático

Um classificador lê o texto das primeiras 1–2 páginas e procura expressões características:

- **Convenção:** "convenção de condomínio", "instituído por escritura pública", referência a
  "art. 1.332" ou "1.334" do Código Civil, cláusulas numeradas por "capítulo".
- **Regimento interno:** "regimento interno", "normas de convivência", "silêncio das
  22h às...", tabela de multas por infração.
- **Ata de assembleia:** "aos [dia] dias do mês de...", "em Assembleia Geral
  Ordinária/Extraordinária", "presidida por", "secretariada por", "lista de presença anexa",
  "foi deliberado".
- **Edital de convocação:** "convocamos os condôminos", "1ª convocação... 2ª convocação",
  "ordem do dia".
- **Balancete:** "balancete", "demonstrativo de receitas e despesas", "saldo anterior", "saldo
  atual", tabela com colunas "conta / previsto / realizado" ou "débito / crédito".
- **Prestação de contas:** "prestação de contas do exercício", "parecer do conselho fiscal
  sobre as contas".
- **Previsão orçamentária:** "orçamento para o exercício", "previsão orçamentária", tabela por
  mês/rubrica sem coluna "realizado".
- **Contrato:** "pelo presente instrumento particular", "contratante" e "contratada",
  "cláusula primeira — do objeto", CNPJ no cabeçalho.
- **Proposta comercial / cotação:** "proposta comercial", "orçamento nº", "validade da proposta",
  "condições de pagamento", "escopo do fornecimento", papel timbrado de empresa com CNPJ, nome e
  contato direto de vendedor no rodapé. **Distinguir do comunicado que a resume:** o comunicado é
  curto (1–2 páginas), é endereçado "aos senhores condôminos" e compara propostas de mais de um
  fornecedor no mesmo arquivo; a proposta é longa, tem um emissor só e fala na primeira pessoa da
  empresa. Na dúvida entre os dois, classificar como proposta — falha para o lado restritivo.
- **Apólice de seguro:** "apólice nº", "seguradora", "importância segurada", "vigência de...a...".
- **Laudo técnico:** "AVCB", "Auto de Vistoria do Corpo de Bombeiros", "laudo de inspeção",
  "ART" ou "RRT", "responsável técnico", "CREA/CFT nº".
- **Notificação/multa:** "notificamos", "em desacordo com o art. [X] do regimento",
  "fica autuado", prazo para defesa.
- **Ata de conselho fiscal:** "reunião do conselho fiscal", "membros do conselho", "parecer do
  conselho".
- **Comunicado avulso:** "informamos", "comunicamos aos senhores condôminos", curto (1–3 páginas),
  assinado pela gestão, **sem** data/hora/local de assembleia + pauta (isso é convocação, não
  comunicado — §14).
- **Comunicado de governança:** "carta de apresentação", "venho comunicar minha renúncia/saída do
  cargo de síndico", "assumo a gestão a partir desta data".
- **Resumo de assembleia:** "resumo da assembleia", "principais pontos discutidos", **ausência** da
  fórmula ritual de abertura de ata ("aos [dia] dias do mês de...", "secretariada por"), sem lista
  de presença formal.
- **Material de apoio de assembleia:** formato slide/apresentação, pouco texto corrido, título
  "Apresentação Reunião/Assembleia" + data.
- **Demonstrativo de composição de cota:** "composição da cota", "demonstrativo de cota
  condominial", tabela rubrica × valor, mês/ano no título.
- **Documento da construtora:** habite-se — "certificado de conclusão", "processo nº"; manual do
  proprietário — "manual do proprietário", versão "V0x"; formulário de garantia — "assistência
  técnica", campos em branco, papel timbrado da construtora.

## Prazo de retenção por tipo

| Tipo | Retenção sugerida |
|---|---|
| Convenção e regimento | Permanente — vigência enquanto não substituídos |
| Atas de assembleia | Permanente [VERIFICAR — livro de atas costuma ser vitalício por prática/exigência cartorial] |
| Editais de convocação | 5 anos após a assembleia correspondente [VERIFICAR] |
| Balancetes | Permanente para série histórica do produto; obrigação legal de guarda contábil costuma ser 5 anos [VERIFICAR prazo fiscal/trabalhista exato] |
| Prestação de contas anual | Permanente |
| Previsão orçamentária | Permanente (comparabilidade histórica) |
| Contratos de fornecedor | Vigência + 5 anos após encerramento [VERIFICAR — prazo prescricional de ação cível] |
| Cotações e propostas comerciais | 5 anos (Lei 4.591/64, art. 22, §1º, "g"); se fundamentaram contrato, vigência do contrato + 5 anos |
| Apólices de seguro | Vigência + 5 anos [VERIFICAR] |
| Laudos técnicos | Até a próxima renovação, mas manter histórico para auditoria de conformidade |
| Notificações e multas | 5 anos [VERIFICAR — prazo prescricional civil, art. 206 CC] |
| Documentação de obras | Permanente (valor probatório de gasto de capital) |
| Atas do conselho fiscal | Permanente, mesma lógica das atas de assembleia |
| Comunicado avulso | 24 meses — decisão de produto, sem obrigação legal identificada |
| Comunicado de governança | Permanente — registro de mandato (CC art. 1.348, VIII / 1.349), mesma lógica de atas e pareceres |
| Resumo de assembleia | Permanente — auditoria de eventual divergência com a ata |
| Material de apoio de assembleia | Permanente — mesma lógica de auditoria da ata |
| Demonstrativo de composição de cota | Permanente — mesma régua de balancete/previsão orçamentária |
| Documento da construtora / entrega de obra | Permanente (produto); prazo de garantia real por item `[VERIFICAR — ver §15]` |

Nenhum desses prazos justifica *exclusão* automática no Breeze — o produto é camada de
auditoria, e histórico é o ativo central. "Retenção" aqui informa obrigação mínima de guarda,
não gatilho de expurgo.

## O que nunca deve ser publicado ao morador comum

Independente do tipo de documento em que apareça, os seguintes dados **nunca** vão para
visibilidade pública nem autenticado-geral — no máximo `conselho`, em regra `restrito`:

- **Folha de pagamento individual** (nome, salário, dados de funcionário) — dado trabalhista de
  terceiro, sem relação com a fiscalização que o morador comum precisa exercer.
- **Inadimplência nominal de terceiros** — morador vê a própria situação e o agregado do
  condomínio; nome + unidade + valor em atraso de outro morador é `conselho`/`editor` (SPEC §5.5
  já trata isso explicitamente).
- **Dado pessoal de representante de fornecedor ou responsável técnico** — CPF, telefone, e-mail
  e assinatura de pessoa natural que não é condômino, típicos de proposta comercial e de laudo.
  Nome do profissional e registro CREA/CFT num laudo podem ficar autenticado, porque são a própria
  validade do laudo; contato direto e CPF, não.
- **Dado de saúde** — qualquer menção a condição médica (ex.: justificativa de afastamento,
  laudo de acessibilidade vinculado a pessoa) é dado sensível por definição legal (LGPD, art. 5º,
  II) e deve ser tratado como `restrito` por padrão, nunca extraído para busca geral.
- **Dado biométrico** — reconhecimento facial, digital, íris etc., quando vinculado a pessoa
  natural identificável, é dado pessoal sensível por definição legal (LGPD, art. 5º, II, que lista
  "dado genético ou biométrico" ao lado de dado de saúde). Um "Comunicado Facial" sobre novo
  sistema de acesso não é, por si, um problema — mas qualquer imagem, template biométrico ou
  identificação nominal de morador dentro dele é. Achado real no acervo (`docs/inventario-acervo.md`,
  item 25): sinalizado para `juridico-lgpd`, não resolvido por esta skill.
- **Imagem de CFTV** — não faz parte do acervo documental do Breeze; se um print entrar
  acidentalmente em algum anexo, tratar como incidente de segurança, não como documento a
  indexar.

Quando um documento público ou autenticado (ata, balancete) contém trechos com esses dados
misturados ao conteúdo normativo, a indexação deve extrair o texto normativo e excluir — não
apenas ocultar na interface — o trecho sensível do índice de busca geral. Atenção à D13: se o
trecho sensível exigir de fato restrição, quem desce é **o documento**, e as demais páginas sobem
por override — nunca o contrário.
