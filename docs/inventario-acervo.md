# Inventário do acervo real — Documentos do Condomínio

Sondagem de metadados dos 43 PDFs em `Documentos do Condomínio/` (extração de texto via
`pypdf`, sem cópia de conteúdo). Nativo/escaneado/misto pela heurística da skill
`ocr-documento-fiscal-br` (qualidade do texto extraído, não só presença de camada); tipo
documental pela taxonomia de `condominio-documentos`. Nenhum trecho com nome, CPF ou valor
individual foi reproduzido.

**Nome de pessoa natural é redigido aqui, e a regra vale para o repositório inteiro.** A tabela
trazia dois nomes próprios vindos do nome de arquivo (carta de renúncia de síndico, carta de
apresentação da gestão) sob o argumento de serem "metadado já público no condomínio". O
argumento caiu quando o repositório virou público em 2026-09-08: público no hall de um prédio
específico e público na internet aberta e indexável não são a mesma exposição, e a segunda não
se desfaz. Os nomes viraram `[NOME]`/`[NOMES]` no HEAD **e em todo o histórico**
(`git filter-repo --replace-text`) — redigir só o arquivo atual seria teatro, porque `git log -p`
mostra o resto.

Ao acrescentar linha nesta tabela: **o nome do arquivo entra sem o nome da pessoa.** Razão
social de fornecedor pode ficar — pessoa jurídica não é titular de dado pessoal (LGPD art. 5º, I).

**Nota metodológica:** o limiar automático de densidade de palavra sinalizou 6 documentos como
"MISTO". Inspeção manual página a página (`repl_ratio` = 0 em todas) mostrou que nenhum é OCR
degradado — são casos de baixa densidade textual por formato (sumário com pontilhado, tabela
numérica densa, capa com espaçamento de letras, formulário em branco, slide gráfico).
Reclassificados como NATIVO na tabela. Achado em si: **nenhum documento apresenta o padrão
mais traiçoeiro da skill (texto nativo herdado de OCR antigo ruim)**, porque não há documento
anterior a 2025 no acervo.

## Tabela por documento

| # | Documento | Tipo (taxonomia) | Pág. | Camada de texto | Tabela financeira | Estrutura de artigos | Visibilidade sugerida |
|---|---|---|---|---|---|---|---|
| 1 | Apresentação Reunião Geral - 12.03.2026.pdf | Material de apoio de assembleia (fora da taxonomia) | 11 | NATIVO (baixo texto, slide gráfico) | Não | Não | Autenticado |
| 2 | Atas/1 - AGI 04.12.2025 SITE.pdf | Ata de assembleia — **AGI, Assembleia Geral de Instalação** (fora da taxonomia atual, só cobre AGO/AGE) | 10 | NATIVO | Sim | Não | Autenticado |
| 3 | Atas/22115 - BREEZE AGE 04.02.2026 site.pdf | Ata de assembleia (AGE) — **embute anexos (convenção, regimento, apólice, laudo)** | 36 | NATIVO | Sim | Sim (191 arts., dos anexos) | Autenticado (anexos deveriam ser público — ver conclusões) |
| 4 | Atas/2215 - BREEZE AGE 27.03.2026 site.pdf | Ata de assembleia (AGE) | 2 | NATIVO | Sim | Não | Autenticado |
| 5 | Atas/2215 - BREEZE AGE 30.04.2026 SITE.pdf | Ata de assembleia (AGE) | 7 | NATIVO | Sim | Não | Autenticado |
| 6 | AVCB-BREEZE-BOSQUE-SAUDE.pdf | Laudo técnico (AVCB) | 1 | NATIVO | Não | Não | Autenticado |
| 7 | Breeze - Formulário Assistência Técnica.pdf | Anexo do Manual do Proprietário (formulário em branco) | 1 | NATIVO | Não | Não | Autenticado |
| 8 | Breeze-Bosque-da-Saude-Convencao-de-Condominio-registrada.pdf | **Convenção de condomínio** | 18 | **ESCANEADO (0 caractere extraído)** | Não | Sim, mas não extraível hoje | Público (bloqueado até OCR) |
| 9 | Comunicados/2215 CARNAVAL - OBRAS E REFORMAS.pdf | Comunicado (fora da taxonomia) | 1 | NATIVO | Não | Não | Autenticado |
| 10 | Comunicados/2215 - CARTA DE RENÚNCIA - SINDICO [NOME].pdf | Comunicado de governança | 2 | NATIVO | Não | Não | Autenticado |
| 11 | Comunicados/… ESCLARECIMENTOS BOLETOS JULHO-2026.pdf | Comunicado financeiro | 3 | NATIVO | Não | Não | Autenticado |
| 12 | Comunicados/… ESCLARECIMENTOS VALORES BOLETOS E AJUSTE ENXOVAL.pdf | Comunicado financeiro | 1 | NATIVO | Não | Não | Autenticado |
| 13 | Comunicados/… PROPOSTAS DAS EMPRESAS DE PORTARIA REMOTA.pdf | Comunicado / cotação de fornecedor | 1 | NATIVO | Não | Não | Autenticado |
| 14 | Comunicados/2215 - Esclarecimentos Portoes Enxoval.PDF | Comunicado | 2 | NATIVO | Não | Não | Autenticado |
| 15 | Comunicados/… LEMBRETE AGE 04.02.2026 (1).pdf | Edital/lembrete de convocação | 1 | NATIVO | Não | Não | Autenticado |
| 16 | Comunicados/… LEMBRETE AGE 04.02.2026.pdf | **Duplicata byte-idêntica do #15** | 1 | NATIVO | Não | Não | Autenticado |
| 17 | Comunicados/2215 - RESUMO DA ASSEMBLEIA 27.03.2026.pdf | Resumo de ata (não é a ata formal) | 1 | NATIVO | Não | Não | Autenticado |
| 18 | Comunicados/2215 COMPOSIÇÃO DA COTA FEVEREIRO 2026.pdf | Demonstrativo de cota (fora da taxonomia) | 1 | NATIVO | Não | Não | Autenticado |
| 19 | Comunicados/2215 COMPOSIÇÃO DA COTA MARÇO 2026.pdf | Demonstrativo de cota | 1 | NATIVO | Não | Não | Autenticado |
| 20 | Comunicados/… liberação dos espaços - CHURRASQUEIRA E SALÃO.pdf | Comunicado operacional | 1 | NATIVO | Não | Não | Autenticado |
| 21 | Comunicados/…COMUNICADO URGENTE – COTA CONDOMINIAL (MARÇO 2026).pdf | Comunicado financeiro | 1 | NATIVO | Não | Não | Autenticado |
| 22 | Comunicados/atestado-brigada-de-incendio-2026-….pdf | Laudo técnico (atestado de brigada) | 1 | NATIVO | Não | Não | Autenticado |
| 23 | Comunicados/CARTA DE APRESENTAÇÃO BREEZE - [NOMES].pdf | Comunicado de governança (apresentação de gestão) | 1 | NATIVO | Não | Não | Autenticado |
| 24 | Comunicados/Comunicado Alteração modalidade reuniao 12_03_26.pdf | Comunicado / edital | 1 | NATIVO | Não | Não | Autenticado |
| 25 | Comunicados/COMUNICADO FACIAL.pdf | Comunicado (provável dado biométrico — ver conclusões) | 1 | **ESCANEADO (0 caractere)** | Não | Não | Autenticado (revisar LGPD) |
| 26 | Comunicados/Comunicado Novo Rateio Enxoval.pdf | Comunicado financeiro | 1 | NATIVO | Não | Não | Autenticado |
| 27 | Comunicados/Comunicado Reunião Sistema Segurança.pdf | Comunicado | 1 | NATIVO | Não | Não | Autenticado |
| 28 | Comunicados/Esclarecimentos Processo Implantacao.pdf | Comunicado financeiro | 2 | NATIVO | Não* | Não | Autenticado |
| 29 | Comunicados/GERENCIA DE ATENDIMENTO - BREEZE.pdf | Comunicado institucional | 1 | NATIVO | Não | Não | Autenticado |
| 30 | Comunicados/RESUMO ASSEMBLEIA 04.02.2026.pdf | Resumo de ata | 3 | NATIVO | Não | Não | Autenticado |
| 31 | Comunicados/RESUMO ASSEMBLEIA 30.04.2026.pdf | Resumo de ata | 2 | NATIVO | Não | Não | Autenticado |
| 32 | Comunicados/Utilizacao Elevadores.pdf | Comunicado operacional | 1 | NATIVO | Não | Não | Autenticado |
| 33 | Habite-se-Breeze-Bosque-Saude.pdf | Certificado de Conclusão (Habite-se) — fora da taxonomia | 4 | NATIVO | Não | Falso positivo (cita art. de norma, não é estrutura própria) | Autenticado |
| 34 | MANUAL DO PROPRIETÁRIO.pdf | Manual do proprietário/garantia — fora da taxonomia | 95 | NATIVO | Não | Não | Autenticado |
| 35 | Orçamentos Segurança/Core Solutions.pdf | Documentação de obras — cotação de fornecedor | 8 | NATIVO | Não | Não | Conselho (proposta comercial concorrente) |
| 36 | Orçamentos Segurança/GPA Engenharia.pdf | Documentação de obras — cotação de fornecedor | 8 | NATIVO | Sim | Não | Conselho |
| 37 | Orçamentos Segurança/Proposta Portaria Remota - FortServ.pdf | Documentação de obras — cotação de fornecedor | 27 | NATIVO | Não | Não | Conselho |
| 38 | PROCEDIMENTOS PARA EXECUÇÃO DE REFORMAS + ANEXOS.pdf | Documentação de obras / regra de reforma | 21 | NATIVO | Não | Falso positivo (1 match) | Autenticado |
| 39 | Prestação de Contas/PrestContas dezembro 2025.pdf | Balancete mensal (nome local = "prestação de contas") | 2 | NATIVO | Sim | Não | Autenticado |
| 40 | Prestação de Contas/PrestContas janeiro 2026.pdf | Balancete mensal | 2 | NATIVO | Sim | Não | Autenticado |
| 41 | Prestação de Contas/PrestContas fevereiro 2026.pdf | Balancete mensal | 2 | NATIVO | Sim | Não | Autenticado |
| 42 | Previsão Orçamentária - Até 3 meses - dez-2025.pdf | Previsão orçamentária (escopo trimestral, não anual) | 4 | NATIVO | Sim | Não | Autenticado |
| 43 | RI - Regulamento Interno - Breeze Bosque da Saúde.pdf | **Regimento interno** | 23 | NATIVO | Não | **Sim — ver correção abaixo** | Público |

\* Menciona balancete/receita/despesa/orçamento em prosa explicativa, mas sem tabela estruturada extraível.

## Conclusões

**O condomínio foi entregue muito recentemente — sim, com evidência forte e convergente.**
O Habite-se traz número de processo `58709-25-SP-CCE` (`-25-` = emissão em 2025, padrão do
Portal do Licenciamento de SP). A primeira ata do acervo é uma **AGI — Assembleia Geral de
Instalação**, 04.12.2025: ato fundacional, não assembleia de condomínio já operando. O Manual
do Proprietário está na versão `V00 – 01/08/25`. Há formulário de assistência técnica (típico
de garantia de construtora em imóvel novo), carta de apresentação da gestão e, poucos meses
depois, carta de renúncia do síndico seguinte — instabilidade comum em primeiros meses. A série
de balancete cobre só três competências (dez/2025 a fev/2026), e a "Previsão Orçamentária" é
explicitamente "até 3 meses", não anual — o condomínio ainda não tem um ano de operação para
orçar. Nenhum documento é anterior a 2025 (só há citação normativa antiga dentro de texto,
como Código Civil 2002). Janela coberta: **dez/2025 a jul/2026, ~8 meses de vida**. Isso muda
decisão de produto: telas que pressupõem histórico multianual não têm dado real ainda — o
produto precisa degradar bem com pouco histórico, não assumir que ele existe.

**OCR: escopo pequeno, mas em documento crítico.** Só 2 dos 43 PDFs são verdadeiramente
ESCANEADOS (0 caractere extraído): a **Convenção registrada** (18 páginas) e um "Comunicado
Facial" (1 página) — 19 páginas, ~4,4% do acervo. Custo trivial (poucos centavos a ~R$5 em
qualquer fornecedor de OCR em nuvem), mas a Convenção é o único documento de visibilidade
pública e está **bloqueada para busca e citação por artigo** até OCR + conferência humana
(SPEC §5.1) — maior prioridade do lote, não pelo volume, por ser o texto normativo-mãe.

**Série financeira insuficiente para média móvel de 6 meses.** Só 3 balancetes mensais
existem. Qualquer alerta que dependa de janela de 6 meses precisa de uma regra explícita de
"dado insuficiente", não de calcular sobre janela parcial — 3 pontos completados com zero ou
extrapolação seria enganoso. Só haverá 6 competências reais por volta de maio/2026.

**Achado estrutural: taxonomia de documento não cobre a maior parte do acervo real.** 24 dos 43
arquivos (56%) estão na pasta "Comunicados" — avisos avulsos de gestão (esclarecimentos de
boleto, lembrete de assembleia, resumo pós-assembleia, liberação de espaço, mudança de sistema
de segurança). Nenhum desses é um dos 13 tipos formais da skill `condominio-documentos`. Da
mesma forma, a AGI (assembleia de instalação) não existe na taxonomia, que só prevê AGO/AGE, e
o Certificado de Conclusão/Habite-se e o Manual do Proprietário — presentes porque o
condomínio é novo — também ficam de fora. Antes de F1, vale decidir se "comunicado" vira um
14º tipo de primeira classe (com sua própria visibilidade e regra de busca) ou se é tratado
como subtipo de edital/ata — hoje nenhuma das duas está definida.

**Achado de arquitetura: um PDF pode conter mais de uma visibilidade.** A ata AGE de
04.02.2026 (36 páginas) embute como anexo o Regimento Interno inteiro — os mesmos 191 artigos
do arquivo autônomo do Regimento aparecem duplicados dentro dessa ata. Como a ata é
autenticada e o Regimento é público, indexar o documento inteiro por `documento_id` único
prenderia texto normativo público atrás de login. O motor de chunking/citação precisa
reconhecer esse tipo de anexo replicado (por hash de trecho ou por detecção de estrutura de
artigo) e herdar a visibilidade do conteúdo, não do documento continente — ou, no mínimo, o
curador precisa sinalizar manualmente esse caso na conferência.

**Outras lacunas para o produto funcionar como especificado:** nenhuma apólice de seguro
autônoma no acervo (só citada dentro de anexo de ata); nenhum contrato de fornecedor assinado
— só cotações da pasta "Orçamentos Segurança", que são propostas concorrentes e não deveriam
ir para visibilidade autenticado-geral enquanto não há decisão (sugiro `conselho` até
aprovação); nenhuma prestação de contas anual nem ata de conselho fiscal, esperado dado que o
condomínio não completou um ano; e há uma duplicata exata (mesmo hash) entre dois arquivos de
lembrete de assembleia — útil como caso de teste real para a deduplicação por `sha256` prevista
na skill de OCR.


---

## Correção de 2026-09-06 — "191 artigos" estava errado

A sondagem contou **ocorrências** da palavra "Art." e reportou 191 artigos no Regimento (e os
mesmos 191 dentro da ata de 04.02.2026, que o embute). Ao chunkizar o documento de verdade, o
número não se sustentou: são **187 linhas que começam com "Artigo"**, mas só **25 números
distintos**, com máximo 393 — porque parte das ocorrências são citações de artigo de norma externa
(Código Civil) e, principalmente, porque o **Regimento reinicia a numeração a cada um dos seus 24
capítulos**. Existem 24 "Artigo 1º" no mesmo documento.

Consequência que não é cosmética: **"Artigo 5º do Regimento" não identifica nada.** A unidade
citável é `capítulo + artigo + página`. Isso está registrado como correção no SPEC §4 e
implementado em `lib/ingestao/chunker.ts` (a seção viaja com o chunk; nenhum chunk atravessa
capítulo).

Lição para a próxima sondagem: contar ocorrência de padrão é medir o texto, não a estrutura. A
estrutura só apareceu quando alguém processou o documento inteiro e olhou a saída.
