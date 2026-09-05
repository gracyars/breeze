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

## 3. Atas de assembleia (AGO/AGE)
- **Periodicidade:** AGO anual (prestação de contas, orçamento, eleição); AGE sob demanda.
- **Produz:** secretário da mesa/síndico, redigida na própria assembleia.
- **Metadados:** tipo (AGO/AGE), data, quórum presente, lista de pauta, `deliberacoes` (item,
  resultado, votos) vinculadas a `chunk_id` para citação exata.
- **Busca típica:** "o que foi decidido sobre X", autorização de gasto, resultado de votação,
  eleição de síndico/conselho.
- **Visibilidade padrão:** autenticado — contém nome e unidade de presentes e votantes.

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
- **Imagem de CFTV** — não faz parte do acervo documental do Breeze; se um print entrar
  acidentalmente em algum anexo, tratar como incidente de segurança, não como documento a
  indexar.

Quando um documento público ou autenticado (ata, balancete) contém trechos com esses dados
misturados ao conteúdo normativo, a indexação deve extrair o texto normativo e excluir — não
apenas ocultar na interface — o trecho sensível do índice de busca geral. Atenção à D13: se o
trecho sensível exigir de fato restrição, quem desce é **o documento**, e as demais páginas sobem
por override — nunca o contrário.
