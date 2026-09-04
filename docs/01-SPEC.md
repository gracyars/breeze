# Breeze — SPEC Técnico e Funcional

Documento-fonte para os agentes. Toda implementação deve citar a seção que a justifica.
Suposições: condomínio único (single-tenant), ~50 unidades, acervo de centenas de PDFs com
parcela escaneada, fluxo incremental baixo (~5–20 documentos/mês).

---

## 1. Arquitetura

### 1.1 Decisões (ADR resumido)

| # | Decisão | Porquê | Descartado |
|---|---|---|---|
| ADR-1 | Next.js App Router + TypeScript na Vercel | Server Components e Server Actions eliminam camada de API; deploy sem infra para manter. | Self-host em VPS — mais superfície de manutenção, zero ganho nesta escala. |
| ADR-2 | Supabase Postgres como datastore único | FTS, pgvector, JSONB, RLS e transações no mesmo lugar. Um backup, um modelo mental. Postgres é portável. | Firebase (sem agregação relacional), Mongo (dado aqui é relacional). |
| ADR-3 | Supabase Auth — entrada por CPF **ou** e-mail, sempre resolvendo em magic link; TOTP obrigatório para `editor` e `conselho` | RLS lê `auth.uid()` nativamente. Senha é passivo num público não-técnico. **CPF não é segredo — nunca autentica sozinho** (ver §2.1). | Clerk/Auth0 (custo e desacoplamento do RLS); CPF+senha (enumeração trivial). |
| ADR-4 | Supabase Storage, buckets privados, upload direto por signed URL | Contorna o limite de body de rota da Vercel. Compatível com S3, migração trivial. | Upload via função Next — quebra em PDF grande. |
| ADR-5 | Busca híbrida: `tsvector` PT-BR + pgvector, fundidos por RRF | FTS falha em paráfrase; vetor falha em identificador exato ("art. 12", "R$ 43.200") — fatal em documento legal. RRF `1/(60+rank)` dispensa calibração de peso. | FTS puro, vetorial puro, motor externo (Elastic/Pinecone: mais um serviço, mais um backup). |
| ADR-6 | Extração nativa primeiro; OCR condicional via API paga | Regra: `< 100 chars/página` **ou** razão alta de gibberish → OCR. Atas antigas frequentemente têm camada de OCR ruim — pior que nenhuma. | Tesseract self-hosted (qualidade inferior em scan torto), OCR em toda página (custo e degradação). |
| ADR-7 | Processamento pesado em worker Node persistente consumindo fila em Postgres; backfill histórico roda local, uma vez | O acervo é finito: um script na máquina do mantenedor resolve o histórico com custo zero. Só o incremental precisa de worker. | Vercel Functions (timeout, binários nativos), Edge Functions (limites para OCR). |

### 1.2 Ambientes e custo

Local (`supabase start`) → staging (Supabase free + preview Vercel) → produção (Supabase Pro).
CI: lint, typecheck, testes de RLS, `supabase db push`. **Schema nunca é editado pelo dashboard** —
só migração versionada; tipos TS gerados no CI.

Recorrente estimado ~R$300/mês (Vercel Pro ~110, Supabase Pro ~140, worker ~15, LLM 20–60,
backup e domínio ~10). Custo único de OCR + embeddings do acervo: R$50–300.

---

## 2. Modelo de dados

`id uuid pk` em todas. **Valor monetário sempre `bigint` em centavos** — nunca float.

| Tabela | Colunas-chave | Índices | RLS |
|---|---|---|---|
| `unidades` | bloco, numero, fracao_ideal, area_m2 | `unique(bloco,numero)` | leitura: autenticados |
| `pessoas` | auth_user_id, nome, email, `cpf_hash` (HMAC determinístico, para lookup), `cpf_enc` (reversível), telefone | `unique(cpf_hash)` | própria linha; `conselho` lê todas sem CPF; CPF em claro só para `editor`, via view |
| `vinculos` | unidade_id, pessoa_id, tipo, inicio, fim | `(unidade_id, fim)` | própria unidade; conselho tudo |
| `papeis` | pessoa_id, papel, mandato_inicio, mandato_fim | `(pessoa_id, mandato_fim)` | escrita só admin |
| `documentos` | tipo, titulo, data_documento, competencia, storage_path, `sha256 unique`, paginas, ocr_aplicado, status, **visibilidade** | `(tipo, data_documento)` | por `visibilidade`: público / autenticado / conselho / restrito |
| `documento_paginas` | documento_id, pagina, texto, texto_nativo, confianca_ocr | `unique(documento_id,pagina)` | **espelha `documentos`** |
| `chunks` | documento_id, pagina_ini, pagina_fim, ordem, texto, `tsv` generated stored, `embedding vector(1536)` | GIN(tsv); HNSW só acima de ~10k linhas | **espelha `documentos` — crítico** |
| `contas` | codigo, nome, natureza, conta_pai_id | árvore | leitura interna |
| `lancamentos` | data_competencia, data_caixa, conta_id, fornecedor_id, historico, `valor_centavos`, tipo, fundo, **documento_id**, pagina_origem, origem, criado_por | `(competencia, conta_id)`, `(fornecedor_id)` | leitura autenticados; **escrita só `editor`**; **sem UPDATE/DELETE — correção por estorno** |
| `lancamento_anexos` | lancamento_id, storage_path, sha256, tipo | — | `conselho` e `editor`; bucket separado |
| `orcamento` | exercicio, conta_id, mes, valor_previsto | `unique(exercicio,conta_id,mes)` | leitura autenticados; escrita `editor` |
| `fornecedores`, `contratos` | cnpj, razao_social; vigencia, valor_mensal, indice_reajuste, documento_id | — | leitura autenticados |
| `cobrancas` | unidade_id, competencia, valor, vencimento, status, valor_pago | `(status, vencimento)` | **morador vê só a própria unidade**; `conselho` e `editor` veem todas |
| `assembleias`, `deliberacoes` | data, tipo, ata_documento_id; item, resultado, votos, **chunk_id** | — | leitura autenticados |
| `questionamentos` | lancamento_id, autor_id, texto, status, resposta, respondido_por, ts | `(status)` | `conselho` e `editor` |
| `alertas` | tipo, severidade, lancamento_id/contrato_id, detalhe jsonb, status, ts | `(status, severidade)` | `conselho` e `editor` |
| `audit.log` | ts, actor, acao, tabela, registro_id, antes jsonb, depois jsonb, ip, `hash_anterior`, `hash_registro` | — | schema `audit` **fora do PostgREST**; `REVOKE UPDATE, DELETE` inclusive para `service_role` |

Orçado×realizado e posição de inadimplência são **views**, não tabelas materializadas.
Não otimizar antes de doer.

### 2.1 Papéis e autenticação

Quatro papéis. O síndico é **terceirizado e não é usuário do sistema** — ele é a entidade
fiscalizada, referenciada em dados (contratos, lançamentos, pareceres), sem conta e sem acesso.

| Papel | Quem | Pode |
|---|---|---|
| `editor` | Hoje: só a dona do projeto. Depois: subsíndica. | Publicar documento, conferir e publicar balancete, orçamento, fornecedores, responder questionamento. Único papel com escrita. |
| `conselho` | Conselho fiscal e subsíndica | Leitura completa do financeiro, incluindo anexos e inadimplência nominal. Abrir questionamento, emitir parecer. **Nenhuma escrita de lançamento.** |
| `morador` | Proprietários e inquilinos | Acervo publicado, financeiro agregado, própria unidade. |
| `sindico_terceirizado` | Administradora / síndico profissional | **Não é conta.** Existe só como referência em `fornecedores` e como sujeito dos alertas. |

**Login por CPF ou e-mail — regra dura de implementação.** CPF não é secreto e é enumerável.
Portanto: o CPF é *alias de identificação*, nunca credencial. O fluxo é sempre
`CPF ou e-mail digitado → lookup em pessoas.cpf_hash (HMAC com pepper no servidor) → magic link
enviado ao e-mail cadastrado`. O CPF jamais concede sessão por si só. Pessoa sem e-mail
cadastrado não entra: a `editor` cadastra. A resposta da tela de login é idêntica para CPF
existente e inexistente — sem isso, a tela vira oráculo de "esta pessoa mora aqui".

`cpf_hash` precisa ser determinístico (HMAC-SHA256 com pepper em variável de ambiente, fora do
banco) para permitir o lookup; `cpf_enc` é a versão reversível, lida só pela `editor`.

---

## 3. Ingestão de documentos

1. **Upload** — browser → signed URL → bucket privado. Server Action cria `documentos` (status `pendente`) e enfileira. Dedupe por `sha256` antes de processar. Falhas prováveis: PDF com senha, corrompido, muito grande.
2. **Extração nativa** — texto por página + rotação. Falhas: tabela de balancete vira sopa de números; duas colunas embaralham ordem.
3. **OCR condicional** — heurística do ADR-6, API externa, grava `confianca_ocr` por página. Falhas: carimbo e assinatura viram ruído; scan torto ou abaixo de 200 DPI; troca de dígito (8/3, 5/6, 0/O). **É por isso que valor financeiro nunca é aceito direto do OCR** — ver §5.1.
4. **Chunking page-aware** — 800–1.200 tokens, ~15% de overlap, quebra preferencial em título ou item de pauta. Cada chunk carrega `pagina_ini/fim`; a citação depende disso.
5. **Classificação** — LLM barato extrai tipo, data, competência, partes. **Sempre confirmado por humano antes de publicar.**
6. **Indexação** — `tsv` por coluna generated; embeddings em lote. Status → `indexado`.

Idempotente: job re-executável por `sha256` + versão do pipeline. Reprocessar tudo deve ser um comando.

---

## 4. Busca

- **Config PT-BR:** configuração customizada encadeando `unaccent` antes de `portuguese_stem` — resolve "sindico"/"síndico".
- **Sinônimos:** Supabase gerenciado não permite arquivo de dicionário (`synonym`/`thesaurus` exigem acesso a `$SHAREDIR`). Solução: tabela `sinonimos` com expansão da query na aplicação — "taxa condominial | cota | rateio", "fundo de reserva | FR", "prestação de contas | balancete", "AGE | assembleia extraordinária". *Confiança média-alta nessa limitação; validar na primeira semana.*
- **Ranking:** RRF sobre as duas listas (top-50 cada) → top-10. `ts_rank_cd` e distância cosseno alimentam ranks, nunca são somados. `pg_trgm` como rede para erro de digitação em nome próprio.
- **Facetas:** tipo, ano, competência, fornecedor, assembleia. Pré-filtro em Postgres antes do vetorial — barato nesta escala.
- **Restrição de infraestrutura:** a skill `postgres-hybrid-text-search` (Timescale, instalada como referência de RRF) pressupõe a extensão `pg_textsearch` (BM25), **indisponível no Supabase gerenciado**. O RRF é aproveitável; a receita não. Manter `tsvector` nativo conforme ADR-5.
- **Roteamento de intenção:** pergunta sobre **valor** ("quanto gastamos com elevador em 2025?") **nunca** é respondida por RAG sobre balancete escaneado — é roteada para SQL sobre `lancamentos`. Pergunta normativa ("posso ter cachorro?") vai para busca semântica sobre convenção e regimento.
- **Síntese:** permitida, com trava. Grounding estrito nos chunks recuperados, citação obrigatória por afirmação (documento + página + trecho literal), recusa explícita quando o acervo não responde. **A UI mostra o trecho original como resultado primário e a síntese como secundária** — o inverso do padrão de chatbot. Disclaimer permanente: não é interpretação jurídica.

---

## 5. Módulo financeiro

### 5.1 Importação assistida do balancete — o ponto mais delicado do produto

A fonte é um PDF da administradora, frequentemente escaneado. OCR erra dígito. A solução **não**
é confiar na extração nem digitar tudo à mão:

1. Extração propõe as linhas (conta, histórico, valor) com nível de confiança por campo.
2. Tela de conferência lado a lado: PDF original à esquerda com a região destacada, linhas
   editáveis à direita.
3. **Travas de consistência antes de publicar:** soma das contas = total do grupo; total de
   receitas − total de despesas = variação de saldo declarada; saldo final do mês anterior =
   saldo inicial do mês. Divergência bloqueia a publicação.
4. Todo lançamento nasce com `documento_id` + `pagina_origem`. Sem fonte, não existe.

### 5.2 Plano de contas (padrão, parametrizável)

Grupo > subgrupo > conta. Receitas: taxa ordinária, fundo de reserva, taxa extraordinária,
fundo de obras, multas e juros, rendimento de aplicação, uso de área comum, outras.
Despesas: pessoal e encargos; administração; manutenção predial; elevadores; limpeza e
conservação; segurança e portaria; água, energia e gás; seguros; jurídico; obras e melhorias;
taxas e tributos. Deve espelhar o plano da administradora — divergência de plano destrói a
comparabilidade.

### 5.3 Motor de alertas — o diferencial

| Alerta | Regra | Severidade |
|---|---|---|
| Despesa sem comprovante | Lançamento pago sem anexo | Alta |
| Estouro de orçamento | Conta atinge 80% do previsto (aviso) / >100% (crítico) | Média / Alta |
| Cotação ausente | Despesa não recorrente acima do limiar parametrizável (sugestão inicial R$5.000) sem 2+ cotações anexadas | Alta |
| Fundo de reserva sem ata | Débito em conta de fundo de reserva sem `deliberacao_id` vinculada | Crítica |
| Contrato vencendo | 30 dias antes do fim da vigência | Média |
| Renovação não deliberada | Contrato acima da alçada renovado sem ata vinculada | Alta |
| Fornecedor não cadastrado | Pagamento a CNPJ ausente de `fornecedores` | Alta |
| Variação atípica | Conta varia >30% sobre a média móvel de 6 meses | Média |
| Fracionamento suspeito | Múltiplos lançamentos, mesma conta e fornecedor, mesmo mês, somando acima do limiar de cotação | Alta |
| Troca de dados bancários | Alteração de conta de fornecedor recorrente (golpe do boleto) | Crítica |

Limiares vivem em tabela de configuração, não em código.

### 5.4 Fiscalização e fluxo

Questionamento do conselho preso ao lançamento (aberto → respondido → resolvido), com
notificação ao responsável. Parecer do conselho versionado por período, com signatários e
anexos. Fechamento mensal trava o período; lançamento retroativo exige reabertura justificada
e auditada. Correção **sempre por estorno**, nunca por edição.

### 5.5 Relatórios

Balancete mensal; demonstrativo de receitas e despesas; orçado vs realizado com variação;
inadimplência **agregada** para todos e **nominal** só para `conselho` e `editor`, com log de acesso;
evolução por conta em série histórica; prestação de contas anual pronta para pauta.

---

## 6. Experiência

### 6.1 Navegação

Morador (barra inferior, 5 itens): Início · **Buscar** · Financeiro · Documentos · Mais.
Buscar é a segunda aba, não um item escondido — é o objetivo do produto.
Gestão (`editor` e `conselho`), com toggle explícito de contexto: Conferir balancete · Alertas ·
Questionamentos · Publicar documento. O `conselho` vê tudo da gestão mas não escreve lançamento.

Nada chega ao morador sem publicação explícita. Rascunho e publicado são estados visualmente
distintos e o rascunho jamais aparece nas telas de consulta.

### 6.2 Busca — hierarquia do resultado

Campo único, sticky, sem botão de submit. Busca a partir do 3º caractere com debounce ~300ms.
Placeholder rotativo com perguntas reais ("posso ter cachorro?", "quanto gastamos com elevador").
Chips horizontais de faceta abaixo do campo, nunca modal.

Resultado: (1) card de resposta direta com citação, quando houver; (2) lista de trechos-fonte com
badge de tipo e data, termo em negrito, ~2 linhas de contexto e link "abrir na página X";
(3) fonte e síntese sempre convivem — em condomínio, confiança vem de *onde está escrito*.
Estado vazio traz perguntas sugeridas por categoria. Sem resultado traz reformulação **e**
"falar com o síndico" — a saída humana precisa estar sempre a um toque.

### 6.3 Documento jurídico legível

Duas colunas no desktop, empilhado no celular: índice colapsável com busca interna + corpo.
Âncora e **permalink por artigo** (essencial para compartilhar no WhatsApp em vez do PDF inteiro).
"Em palavras simples" por artigo, em accordion fechado por padrão, com selo visual permanente
"Resumo — não substitui o texto oficial". O texto oficial nunca é reescrito. Rodapé com versão
vigente, ata que aprovou e link para o PDF original.

### 6.4 Financeiro para leigos

Três camadas: (1) número único do mês com selo; (2) "para onde foi o dinheiro" em barras
horizontais ordenadas do maior para o menor, com valor e % rotulados na barra; (3) orçado vs
realizado em barras pareadas, com badge textual "dentro" / "acima do orçamento".
Evitar pizza, múltiplas séries sobrepostas e qualquer gráfico sem rótulo direto no elemento.
Cada categoria é clicável até o lançamento individual e daí até o comprovante.
Termo contábil sempre com glossário inline.

### 6.4-bis Direito de acesso vs. exigir contas — restrição de copy

STJ, REsp 2.050.372 (3ª Turma, 2023) separa duas coisas que o produto tende a fundir:
**inspecionar documentos** é direito individual de qualquer condômino; **exigir prestação de
contas** é direito coletivo, cuja destinatária é a assembleia — condômino sozinho não tem
legitimidade. Consequência direta: nenhuma tela, botão ou microcopy pode sugerir que um morador
individual "cobra contas" do síndico. O verbo do morador é *consultar*; o de exigir é da
assembleia, e o de questionar formalmente é do `conselho`. O agente `microcopy` deve tratar isso
como restrição, não como preferência de estilo.

### 6.5 Acessibilidade e confiança

Corpo mínimo 16px (alvo 18px), escalável a 200% sem quebra. Contraste AA mínimo, AAA em texto
financeiro. Alvo de toque ≥48px com espaçamento generoso. Verbo claro no botão ("Ver boleto",
nunca "Acessar módulo financeiro"). Todo dado exibe data de publicação, quem publicou, badge
"documento oficial" vs "resumo auxiliar" e link para a fonte. **Nenhum número aparece sem
proveniência rastreável.**

### 6.6 Direção visual

Institucional-sereno, não startup. Base neutra cinza-azulada quase papel; **um único azul
profundo** como cor de ação, sem gradiente. Verde e vermelho reservados exclusivamente a status
financeiro, nunca decorativos. Serifada ou humanista no corpo de texto jurídico, sans-serif
neutra em UI e números. Ícones lineares, sem mascote. Hierarquia por peso tipográfico e espaço
em branco, não por cor. A régua: deve parecer confiável como um extrato bancário.

---

## 7. Segurança e LGPD

- **RLS negando por padrão** em todas as tabelas, com helper `papel_atual(uid)` lendo mandato vigente. Testes de policy (pgTAP) versionados e rodando no CI — regressão de RLS é vazamento.
- **Armadilha nº1:** RLS em `documentos` sem RLS equivalente em `chunks` e `documento_paginas` vaza conteúdo restrito pela busca. Espelhar sempre.
- **Anexos financeiros** em bucket próprio, acesso só por signed URL de TTL curto (60–300s) gerada no servidor após checagem de papel. Nunca embutida em página cacheada na CDN.
- **Trilha imutável:** triggers `SECURITY DEFINER` gravam em `audit.log`; encadeamento `hash_registro = sha256(hash_anterior || linha canônica)`; âncora semanal do hash-topo enviada por e-mail ao conselho. Assim, adulteração por quem tem acesso ao banco — inclusive a `editor` — fica detectável. Isso é o que dá ao produto autoridade perante os moradores: nem quem opera o sistema pode reescrever o passado sem deixar rastro.
- **Base legal LGPD:** obrigação legal e legítimo interesse (dever de prestar contas do síndico, **Código Civil art. 1.348, VIII** — confirmado em fonte primária), **não** consentimento. Minimização: CPF em claro visível apenas ao `editor`; para o `conselho`, sempre mascarado.
- **Inadimplência nominal jamais é exposta a moradores.** Morador vê apenas a própria unidade.
- **Visibilidade pública:** por padrão, apenas convenção e regimento (normativos e impessoais). Ata e balancete exigem autenticação — contêm nome, unidade e às vezes CPF. Se a decisão for publicar acervo aberto, é obrigatória etapa de redação/anonimização antes da publicação. *Ver decisão pendente nº1 no briefing.*
- **Retenção:** piso legal de 5 anos vem da **Lei 4.591/64, art. 22, §1º, alínea "g"** — único piso explícito de guarda documental condominial, que sobreviveu à derrogação pelo Código Civil. Atas, convenção e laudos permanentes por **decisão de produto**, não por obrigação legal comprovada. Log de acesso 6 meses. Guarda de folha, ponto e registro de empregados: `[NÃO CONFIRMADO — verificar]`. Atenção: a Lei 8.212/91 art. 32, §11 **não diz mais "dez anos"** desde a Lei 11.941/2009 — hoje é "até que ocorra a prescrição"; quase toda fonte secundária de contabilidade ainda repete os 10 anos. Rotina de anonimização de ex-morador preserva agregados e apaga PII.
- **Backup:** backup do provedor não é backup. `pg_dump` semanal + espelho do Storage em conta separada, com restore testado trimestralmente.

---

## 8. Riscos, por severidade

1. **Vazamento de dado pessoal** por RLS ausente em `chunks` ou Storage → negação por padrão + teste de policy no CI.
2. **Alucinação em pergunta jurídica** levando a decisão errada em assembleia → trecho original primário, citação obrigatória, recusa, zero síntese para valores.
3. **OCR ruim em atas antigas** → score de confiança por página, revisão humana das atas estruturantes, valores só do fluxo estruturado.
4. **Divergência entre o publicado e o balancete da administradora** destrói a credibilidade do produto → travas de consistência do §5.1 e conciliação mensal fechada.
5. **Bus factor = 1** com dado do condomínio dentro → backup em conta de terceiro, runbook de restauração, export completo em um comando.
6. **Editora única com acesso total** — quem publica é também quem seria auditada → hash-chain com âncora semanal fora do sistema; papel `conselho` com leitura completa e independente.
7. **Custo de LLM crescendo** → cache de consultas frequentes, teto mensal, modelo pequeno na classificação.

---

## 9. Fases

**F0 — Fundação:** repo, ambientes, schema, RLS + testes de policy, auth, design tokens.
**F1 — Acervo:** upload, pipeline de ingestão, backfill do histórico, busca híbrida, leitor de documento.
**F2 — Financeiro:** plano de contas, importação assistida do balancete, painel para leigos, orçado vs realizado.
**F3 — Fiscalização:** motor de alertas, questionamentos, parecer do conselho, trilha auditável exposta.
**F4 — Endurecimento:** acessibilidade, QA E2E, backup e restore testado, onboarding dos moradores.

Fim de F1 já é um produto útil sozinho. Não avançar para F2 antes de o acervo estar de fato em uso.
