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

Esta tabela é o resumo. Os ADRs completos — contexto, consequências e alternativas descartadas —
vivem em `docs/adr/`, numerados de 0001 a 0016, e são a fonte quando houver dúvida. Além dos sete
acima, F0 decidiu: estratégia de migração (0008), política de ambientes (0009), representação
monetária (0010), imutabilidade de lançamento (0011), RLS como fronteira única (0012), auditoria
encadeada (0013), tratamento de CPF (0014) e enum vs. tabela de domínio (0015).

### 1.2 Ambientes e custo

Local (`supabase start`) → staging (Supabase free + preview Vercel) → produção (Supabase Pro).
CI: lint, typecheck, testes de RLS, `supabase db push`. **Schema nunca é editado pelo dashboard** —
só migração versionada; tipos TS gerados no CI.

Recorrente estimado ~R$300/mês (Vercel Pro ~110, Supabase Pro ~140, worker ~15, LLM 20–60,
backup e domínio ~10). Custo único de OCR + embeddings do acervo: R$50–300.

---

## 2. Modelo de dados

`id uuid pk` em todas. **Valor monetário sempre `bigint` em centavos** — nunca float — e a
coluna **carrega o sufixo `_centavos`**: `valor` sozinho não diz a unidade, e erro de unidade é
invisível até virar 100× num relatório (ADR-0010).

Desenho completo em DDL comentado: `docs/schema.md`. A tabela abaixo é o índice; ela e o schema
não podem divergir.

| Tabela | Colunas-chave | Índices | RLS |
|---|---|---|---|
| `unidades` | bloco, `numero text` (existe "101-A", "Cob 02"), ordem, fracao_ideal, area_m2 | `unique(bloco,numero)` | leitura: autenticados; escrita `editor` |
| `pessoas` | auth_user_id, nome, email, `cpf_hash` (HMAC determinístico, para lookup), `cpf_enc` (reversível), `cpf_ultimos_digitos`, telefone | `unique(cpf_hash)` | própria linha; `conselho` lê todas com CPF mascarado; CPF em claro só para `editor`, **decifrado em rotina de servidor** e registrado em `audit.acesso` — `cpf_enc` sem `SELECT` para `authenticated` |
| `vinculos` | unidade_id, pessoa_id, tipo, inicio, fim | `(unidade_id, fim)` | própria unidade; conselho tudo |
| `papeis` | pessoa_id, papel, mandato_inicio, mandato_fim, concedido_por | `(pessoa_id, mandato_fim)`, `(papel, mandato_inicio, mandato_fim)` | leitura: próprios papéis, gestão vê todos; **escrita só `editor` com AAL2** |
| `tipos_documento` | codigo, nome, visibilidade_padrao, `permite_publico`, retencao_meses | pk textual | leitura livre; escrita `editor`. Tabela de domínio: taxonomia cresce sem deploy |
| `documentos` | tipo, titulo, data_documento, competencia, storage_path, `sha256 unique`, paginas, ocr_aplicado, status, **visibilidade**, **tem_paginas_mistas**, versao_pipeline | `(tipo, data_documento)`, `(visibilidade, status)` | por `visibilidade`: público / autenticado / conselho / restrito — arquivo inteiro via `app.documento_visivel()` |
| `documento_unidades` | documento_id, unidade_id | pk composta | leitura: própria unidade + gestão. **Sem ela, `visibilidade='restrito'` não é avaliável** |
| `documento_paginas` | documento_id, pagina, texto, texto_nativo, fonte_texto, confianca_ocr, **visibilidade** (override, nullable) | `unique(documento_id,pagina)` | **espelha `documentos`, por página** — `app.pagina_visivel()` |
| `chunks` | documento_id, pagina_ini, pagina_fim, ordem, texto, `tsv` generated stored, `embedding vector(1536)` | GIN(tsv); HNSW só acima de ~10k linhas | **espelha `documentos` por página, via `pagina_ini` — crítico**; chunk não cruza fronteira de visibilidade |
| `contas` | codigo, nome, natureza, nivel, conta_pai_id, aceita_lancamento, codigo_administradora | árvore, `(codigo text_pattern_ops)` | leitura autenticados; escrita `editor`. **Não carrega regra de fiscalização** (§5.3) |
| `fornecedores` | cnpj, `cpf_hash`, razao_social, `eh_sindico_terceirizado`, `eh_administradora` | `unique(cnpj)`, trigram(razao_social) | leitura autenticados (sem `cpf_enc`); escrita `editor` |
| `fornecedor_dados_bancarios` | fornecedor_id, banco, agencia, conta_mascarada, `chave_pix_hash`, vigencia | `(fornecedor_id, vigente_ate)` | só `conselho` e `editor`. Existe para o alerta "troca de dados bancários"; nada em claro |
| `contratos` | fornecedor_id, objeto, vigencia, `valor_mensal_centavos`, indice_reajuste, documento_id, deliberacao_id | `(vigencia_fim)` parcial | leitura autenticados |
| `periodos_fechados` | competencia pk, fechado_por, saldo_inicial/final, reaberto_em, motivo_reabertura | pk | leitura autenticados; escrita `editor`. Trava o mês (§5.4) |
| `lancamentos` | data_competencia, data_caixa, conta_id, fornecedor_id, historico, `valor_centavos`, tipo, fundo, **documento_id**, pagina_origem, origem, **deliberacao_id**, **estorna_lancamento_id**, motivo_estorno, criado_por | `(competencia, conta_id)`, `(conta_id, competencia)`, `(fornecedor_id)` | leitura autenticados; **escrita só `editor`**; **sem UPDATE/DELETE — correção por estorno** (§5.4) |
| `lancamento_anexos` | lancamento_id, storage_path, sha256, tipo | `(lancamento_id)`, parcial `tipo='cotacao'` | `conselho` e `editor`; bucket separado |
| `orcamento` | exercicio, conta_id, mes, `valor_previsto_centavos` | `unique(exercicio,conta_id,mes)` | leitura autenticados; escrita `editor` |
| `cobrancas` | unidade_id, competencia, `valor_centavos`, vencimento, status, `valor_pago_centavos` | `(status, vencimento)`, `unique(unidade_id,competencia)` | **morador vê só a própria unidade**; `conselho` e `editor` veem todas |
| `assembleias` | tipo, data, ata_documento_id, edital_documento_id, quorum_presente | `(data)` | leitura autenticados |
| `deliberacoes` | assembleia_id, item, descricao, resultado, votos, `valor_autorizado_centavos`, **âncora de citação: documento_id + pagina + trecho_literal**, `chunk_id` (ponteiro fraco) | `unique(assembleia_id,item)` | espelha a visibilidade do documento citado |
| `questionamentos` | lancamento_id, autor_id, texto, status, resposta, respondido_por, ts | `(status)` | `conselho` e `editor` |
| `tipos_alerta` | codigo, nome, severidade_padrao, descricao_regra, `requer_historico_meses` | pk textual | leitura gestão; escrita `editor` |
| `alertas` | tipo, severidade, lancamento_id/contrato_id/fornecedor_id, detalhe jsonb, status, `chave_dedupe unique`, ts | `(status, severidade)` | `conselho` e `editor` |
| `pareceres`, `parecer_signatarios` | competencia, versao, texto, conclusao, status; signatário: pessoa_id **+ `nome_signatario` e `qualificacao` congelados na assinatura** | `unique(competencia,versao)` | rascunho: gestão; emitido: autenticados. Única escrita do `conselho` |
| `sinonimos` | termo, termo_normalizado, expansoes[] | `unique(termo_normalizado)` | leitura livre; escrita `editor` |
| `configuracoes` | chave pk, valor jsonb, publica | pk | linha `publica`: autenticados; demais: gestão. **Limiar de alerta vive aqui, não em código** |
| `job.fila` | tipo, payload, status, tentativas, disponivel_em, `chave_idempotencia unique` | parcial `status='pendente'` | schema `job` **fora do PostgREST**; só o worker |
| `audit.log` | seq, ts, actor, acao, tabela, registro_id, antes jsonb, depois jsonb, ip, `hash_anterior`, `hash_registro` | `(tabela, registro_id)` | schema `audit` **fora do PostgREST**; append-only encadeado, **permanente**; `REVOKE UPDATE, DELETE` inclusive para `service_role`, mais trigger que bloqueia o dono da tabela |
| `audit.acesso` | ts, actor, recurso, recurso_id, motivo, ip | `(recurso, ts)` | mesmo isolamento; **sem encadeamento, expurgável em 6 meses**. Separada de `audit.log` porque expurgo e cadeia de hash são incompatíveis (§7) |

Orçado×realizado e posição de inadimplência são **views**, não tabelas materializadas.
Não otimizar antes de doer.

**Visibilidade é resolvida por página, não só por documento.** O acervo real trouxe uma ata de 36
páginas que embute o Regimento Interno inteiro como anexo: um `documento_id` com conteúdo que
deveria ser público (o regimento, normativo e impessoal) e conteúdo que exige autenticação (a ata,
com nomes e votos). Marcar o documento inteiro como público vaza nomes pela busca; marcar como
autenticado esconde o regimento — que é justamente o que o produto existe para tornar consultável.
Por isso: `documentos.tem_paginas_mistas` mais `documento_paginas.visibilidade` (override
nullable), com duas entradas de RLS — `app.documento_visivel(id)` para o arquivo inteiro (o PDF
cru não é fatiado: ninguém baixa a ata porque 12 páginas são públicas) e
`app.pagina_visivel(documento_id, pagina)` para texto extraído, busca e citação. Enquanto
`tem_paginas_mistas` for true, página **sem** classificação própria **não herda** o padrão do
documento. E um chunk não pode cruzar fronteira de visibilidade: com ~15% de overlap (§3.4), o
chunk atravessa página por construção, e sem trava o vazamento seria o padrão.

**A visibilidade do documento é o piso — sem isso, o resto é ilusório.** Regra dura:
`ordem(documentos.visibilidade) <= ordem(qualquer página sua)`, com
`conselho < restrito < autenticado < publico` (atenção: **`restrito` é mais permissivo que
`conselho`**, porque acrescenta a unidade vinculada à gestão — o nome engana). Ou seja: **override
de página só amplia o alcance do texto derivado, nunca o reduz.** O motivo é físico: o PDF é
atômico e o gate do bucket é o do documento; sem essa invariante, um documento `publico` com uma
página `conselho` negava o texto na busca **e entregava o arquivo inteiro para anônimo**. Quando
for preciso restringir de fato uma página, desce-se o documento inteiro e ampliam-se as demais
páginas — o corpo continua legível e citável, e o arquivo acompanha sua página mais sensível.
`tem_paginas_mistas` é **derivada** (ligada por trigger ao surgir o primeiro override), nunca uma
caixinha que alguém precisa lembrar de marcar para a trava funcionar. Detalhes em ADR-0018,
ADR-0019 e `docs/schema.md`.

**PII denormalizada: uma exceção, com critério fechado.** O nome do signatário de parecer é
copiado para `parecer_signatarios` e congelado no momento da assinatura. É a **única** PII
denormalizada do schema. Motivo: a identidade do signatário existia só por chave estrangeira para
`pessoas`, e a anonimização do ex-morador (§7) transformava o signatário em "ANONIMIZADO" —
parecer sem signatário identificável não tem valor probatório, e com editora única (D4) o parecer
do conselho é justamente a peça de contrapeso. Base legal para reter contra pedido de eliminação:
LGPD art. 16, I, porque a assinatura é a validade do ato (CC art. 1.356). Limite estreito, por
necessidade (LGPD art. 6º, III): congela-se nome e qualificação, **nunca** CPF, e-mail, telefone
ou unidade. **Não é precedente** — qualquer outra denormalização de dado pessoal exige os três
testes do ADR-0020 (o dado é elemento do ato; há base legal que impede eliminar; o valor certo é o
do momento do ato), e qualquer "não" significa chave estrangeira.

**Âncora de citação.** Chunk é derivado e regenerável: o pipeline é idempotente e reprocessar
reescreve a segmentação (§3). Portanto nenhuma citação persistida é ancorada em `chunk_id`. A
âncora estável é `(documento_id, pagina)` mais `trecho_literal` guardado como snapshot; `chunk_id`
permanece como ponteiro fraco (`on delete set null`), reconstruível por busca do trecho. Vale para
`deliberacoes` e para qualquer citação futura.

### 2.1 Papéis e autenticação

**Três papéis de usuário.** O síndico é **terceirizado e não é usuário do sistema** — ele é a
entidade fiscalizada, referenciada em dados (contratos, lançamentos, pareceres), sem conta e sem
acesso. `sindico_terceirizado` **não existe no enum `papel`**: valor de enum é convite a criar
conta. Ele é o atributo `fornecedores.eh_sindico_terceirizado`.

| Papel | Quem | Pode |
|---|---|---|
| `editor` | Hoje: só a dona do projeto. Depois: subsíndica. | Publicar documento, conferir e publicar balancete, orçamento, fornecedores, responder questionamento. Único papel com escrita de lançamento. |
| `conselho` | Conselho fiscal e subsíndica | Leitura completa do financeiro, incluindo anexos e inadimplência nominal. Abrir questionamento, emitir parecer. **Nenhuma escrita de lançamento.** |
| `morador` | Proprietários e inquilinos | Acervo publicado, financeiro agregado, própria unidade. |
| *(não é papel)* | Administradora / síndico profissional | **Não é conta.** Existe só como referência em `fornecedores` e como sujeito dos alertas. |

**Login por CPF ou e-mail — regra dura de implementação.** CPF não é secreto e é enumerável.
Portanto: o CPF é *alias de identificação*, nunca credencial. O fluxo é sempre
`CPF ou e-mail digitado → lookup em pessoas.cpf_hash (HMAC com pepper no servidor) → magic link
enviado ao e-mail cadastrado`. O CPF jamais concede sessão por si só. Pessoa sem e-mail
cadastrado não entra: a `editor` cadastra. A resposta da tela de login é idêntica para CPF
existente e inexistente — sem isso, a tela vira oráculo de "esta pessoa mora aqui".

`cpf_hash` precisa ser determinístico (HMAC-SHA256 com pepper em variável de ambiente, fora do
banco) para permitir o lookup; `cpf_enc` é a versão reversível, lida só pela `editor`.

**Onde a cripto acontece — regra dura.** HMAC e cifra rodam **na aplicação**, nunca em função
SQL: o banco recebe `bytea` pronto e nenhum segredo entra nele. Consequência direta: **não existe
view que devolva CPF em claro** — com a chave fora do banco, nenhuma view consegue decifrar, e
RLS não filtra coluna. O acesso ao CPF em claro é uma rotina de servidor que (a) confirma `editor`
com AAL2, (b) decifra, (c) registra em `audit.acesso` com motivo. `cpf_enc` fica **fora da lista
de colunas do `GRANT SELECT`** — não por `REVOKE` de coluna, que não funciona (ADR-0017).
Para o `conselho`, a exibição usa
`cpf_ultimos_digitos` (`***.***.789-**`), que guarda os dígitos 7–9 e **jamais** os
verificadores. Ver ADR-0014.

**Nível de garantia entra na autorização, não só na tela.** TOTP obrigatório para `editor` e
`conselho` significa que o helper de RLS só reconhece esses papéis quando o JWT traz `aal2`;
sessão de membro do conselho em AAL1 é tratada como `morador`. E **papel é dado, não claim**:
vive em `papeis` com mandato datado, não em `app_metadata` — mandato que termina hoje deixa de
valer hoje, sem esperar a expiração do token. Ver ADR-0003 e ADR-0012.

---

## 3. Ingestão de documentos

1. **Upload** — browser → signed URL → bucket privado. Server Action cria `documentos` (status `pendente`) e enfileira. Dedupe por `sha256` antes de processar. Falhas prováveis: PDF com senha, corrompido, muito grande.
2. **Extração nativa** — texto por página + rotação. Falhas: tabela de balancete vira sopa de números; duas colunas embaralham ordem.
3. **OCR condicional** — heurística do ADR-6, API externa, grava `confianca_ocr` por página. Falhas: carimbo e assinatura viram ruído; scan torto ou abaixo de 200 DPI; troca de dígito (8/3, 5/6, 0/O). **É por isso que valor financeiro nunca é aceito direto do OCR** — ver §5.1.
4. **Chunking page-aware** — 800–1.200 tokens, ~15% de overlap, quebra preferencial em título ou item de pauta. Cada chunk carrega `pagina_ini/fim`; a citação depende disso.
5. **Classificação** — LLM barato extrai tipo, data, competência, partes. **Sempre confirmado por humano antes de publicar.**
6. **Indexação** — `tsv` por coluna generated; embeddings em lote. Status → `indexado`.

Idempotente: job re-executável por `sha256` + versão do pipeline. Reprocessar tudo deve ser um comando.

**Aviso a quem for escrever o chunker — você vai encontrar isto.** A ordem real do fluxo é
**chunkizar primeiro, classificar visibilidade depois**: o worker indexa, a curadoria marca as
páginas em seguida. Consequências que não são opcionais:

1. Em documento misto, o chunk **não pode cruzar fronteira de visibilidade** — e com ~15% de
   overlap (item 4 acima) ele atravessa página por construção. O trigger rejeita a inserção; o
   chunker precisa quebrar na fronteira.
2. **Reclassificar uma página apaga os chunks que a intersectam e reenfileira o documento.** Não é
   erro, é o desenho: bloquear a reclassificação quebraria a curadoria, então o derivado é
   invalidado em vez do fluxo. Durante o reprocessamento a busca fica com lacuna naquele documento,
   e **a UI precisa dizer "reindexando"**, não mostrar acervo incompleto sem explicação.
3. O reprocessamento é idempotente por `sha256` + `versao_pipeline`, então reenfileirar é seguro.

Fundamento e o padrão por trás: `docs/adr/0021-invariante-de-dois-lados.md`. As mensagens de
exceção dos triggers citam esse caminho — é onde você vai cair primeiro.

---

## 4. Busca

- **Config PT-BR:** configuração customizada encadeando `unaccent` antes de `portuguese_stem` — resolve "sindico"/"síndico".
- **Sinônimos:** Supabase gerenciado não permite arquivo de dicionário (`synonym`/`thesaurus` exigem acesso a `$SHAREDIR`). Solução: tabela `sinonimos` com expansão da query na aplicação — "taxa condominial | cota | rateio", "fundo de reserva | FR", "prestação de contas | balancete", "AGE | assembleia extraordinária". *Confiança média-alta nessa limitação; validar na primeira semana.*
- **Ranking:** RRF sobre as duas listas (top-50 cada) → top-10. `ts_rank_cd` e distância cosseno alimentam ranks, nunca são somados. `pg_trgm` como rede para erro de digitação em nome próprio.
- **Facetas:** tipo, ano, competência, fornecedor, assembleia. Pré-filtro em Postgres antes do vetorial — barato nesta escala.
- **Restrição de infraestrutura:** a skill `postgres-hybrid-text-search` (Timescale, instalada como referência de RRF) pressupõe a extensão `pg_textsearch` (BM25), **indisponível no Supabase gerenciado**. O RRF é aproveitável; a receita não. Manter `tsvector` nativo conforme ADR-5.
- **Roteamento de intenção:** pergunta sobre **valor** ("quanto gastamos com elevador em 2025?") **nunca** é respondida por RAG sobre balancete escaneado — é roteada para SQL sobre `lancamentos`. Pergunta normativa ("posso ter cachorro?") vai para busca semântica sobre convenção e regimento.
> **Correção, 2026-09-06 (D17, ADR-0024).** A citação por **artigo** não serve para toda fonte
> normativa deste condomínio. A Convenção registrada **não é articulada**: são 2 ocorrências de
> "Art." em 58 mil caracteres, e a estrutura real é `cláusula 1.` → `item a)` → `subitem i.`. Quem
> tem 191 artigos é o Regimento Interno. Logo a citação da Convenção é **cláusula + item + página**,
> e a skill `rag-citacao-juridica-ptbr` precisa do formato antes de a busca citar Convenção. O
> agravante: o marcador de item é justamente o token que o OCR mais erra (`ii.` chega como `il.`),
> e é por isso que `lib/ocr/marcadores.ts` existe.
>
> **Emenda, mesma data, medida ao chunkizar o Regimento real.** O Regimento **é** articulado, mas
> **reinicia a numeração de artigo a cada capítulo**: 24 capítulos, 187 linhas de artigo e apenas
> 25 números distintos — existem 24 "Artigo 1º". Citar "Artigo 5º do Regimento" não identifica
> nada. A citação exige **capítulo + artigo + página**, e por isso o capítulo viaja com o chunk
> (`chunks` carrega a seção) e **nenhum chunk atravessa capítulo** — um chunk que começasse no
> Cap. V e terminasse no Cap. VII citaria, com o rótulo do primeiro, um artigo que existe no
> segundo e diz outra coisa. Errar assim é pior que não achar.

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
| Fundo de reserva sem ata | `lancamentos.fundo <> 'nenhum'` **e** `tipo = 'despesa'` **e** `deliberacao_id` nulo — **independente da conta debitada** | Crítica |
| Contrato vencendo | 30 dias antes do fim da vigência | Média |
| Renovação não deliberada | Contrato acima da alçada renovado sem ata vinculada | Alta |
| Fornecedor não cadastrado | Pagamento a CNPJ ausente de `fornecedores` | Alta |
| Variação atípica | Conta varia >30% sobre a média móvel de 6 meses | Média |
| Fracionamento suspeito | Múltiplos lançamentos, mesma conta e fornecedor, mesmo mês, somando acima do limiar de cotação | Alta |
| Troca de dados bancários | Alteração de conta de fornecedor recorrente (golpe do boleto) | Crítica |

Limiares vivem em tabela de configuração (`configuracoes`), não em código.

**Regra de fiscalização se avalia sobre o atributo do fato, nunca sobre a classificação da
conta.** Correção de modelagem, não de redação: a versão anterior deste documento apoiava o alerta
de fundo em `contas.exige_deliberacao` — uma flag fixa na conta. Está errado. Qualquer despesa
pode ser paga com fundo de reserva: uma bomba queimada em emergência tanto quanto uma obra
planejada. Amarrar a regra a um conjunto fechado de contas produz **falso negativo silencioso** —
o alerta não dispara justamente para o gasto que ninguém previu, que é o que mais interessa
fiscalizar. E cria uma fiscalização que depende de alguém ter marcado a caixinha certa antes;
quem quer escapar não marca. `contas.fundo` e `contas.exige_deliberacao` saem do modelo, e com
elas a conta sintética "2.12 Uso de fundos": uso de fundo é a despesa finalística de sempre
(elevador, obra, hidráulica) com a origem do recurso marcada em `lancamentos.fundo` — preserva
"o quê" foi comprado e "de onde" saiu o dinheiro, sem duplicar valor no resultado nem divergir do
balancete da administradora. Aporte **ao** fundo não exige ata; o que exige é a **saída**. Ver
`docs/04-DECISOES.md` D12 e `docs/dominio/plano-de-contas-decisoes.md`.

**Alerta que depende de histórico.** "Variação atípica" pressupõe média móvel de 6 meses e
"fracionamento suspeito" pressupõe base de comparação; num condomínio recém-entregue esse
histórico não existe, e uma regra sem base produz falso positivo em série — que é como um painel
de alertas perde a confiança do conselho e vira ruído ignorado. Cada regra declara em
`tipos_alerta.requer_historico_meses` quanto de série precisa; o motor **não avalia** a regra
enquanto o acervo não alcança esse mínimo, e a UI diz "aguardando histórico" em vez de silenciar.
*Profundidade real do histórico deste condomínio: `[PENDENTE — decisão da dona do projeto]`,
relacionada ao Briefing §7 item 4.*

### 5.4 Fiscalização e fluxo

Questionamento do conselho preso ao lançamento (aberto → respondido → resolvido), com
notificação ao responsável. Parecer do conselho versionado por período, com signatários e
anexos. Fechamento mensal trava o período; lançamento retroativo exige reabertura justificada
e auditada. Correção **sempre por estorno**, nunca por edição.

**Como o estorno é modelado.** O estorno é um lançamento comum na própria tabela `lancamentos`,
com `estorna_lancamento_id` (self-FK, `unique`) e **valor negativo** exato do original, herdando
conta, tipo e fundo — estorno não reclassifica. Assim `SUM(valor_centavos)` já sai correto sem
cláusula especial, e nenhum relatório futuro erra por esquecer de filtrar estornado. Estorno de
estorno é proibido; um lançamento é estornado no máximo uma vez; o motivo é obrigatório. O par
original+estorno **aparece na UI** — a correção é mostrada, não escondida. Ver ADR-0011.

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
profundo** como cor de ação, sem gradiente. Verde e vermelho **nunca decorativos** — só onde carregam
significado: status financeiro, erro, confirmação. Cor como enfeite é proibida; cor como
semântica é obrigatória e vem sempre acompanhada de texto, para quem não a distingue. Serifada ou humanista no corpo de texto jurídico, sans-serif
neutra em UI e números. Ícones lineares, sem mascote. Hierarquia por peso tipográfico e espaço
em branco, não por cor. A régua: deve parecer confiável como um extrato bancário.

---

## 7. Segurança e LGPD

- **RLS negando por padrão** em todas as tabelas, com helper `papel_atual(uid)` lendo mandato vigente. Testes de policy (pgTAP) versionados e rodando no CI — regressão de RLS é vazamento.
- **Armadilha nº1:** RLS em `documentos` sem RLS equivalente em `chunks` e `documento_paginas` vaza conteúdo restrito pela busca. Espelhar sempre — e espelhar **chamando a mesma função**, nunca copiando o predicado, porque cópia diverge e diverge calado.
- **Armadilha nº1, forma sutil (ADR-0018):** com visibilidade por página, há **duas** entradas de RLS. `app.documento_visivel(id)` governa a linha e o arquivo (bucket `documentos`); `app.pagina_visivel(documento_id, pagina)` governa `documento_paginas`, `chunks` (pela `pagina_ini`) e `deliberacoes`. Usar a entrada de documento onde cabia a de página publica a ata junto com o regimento embutido. O núcleo do mapeamento nível → papel continua em uma função só (`app.nivel_visivel`). Página sem classificação em documento misto **nega por padrão**, e chunk não cruza fronteira de visibilidade.
- **Restrição por página é ilusória enquanto o arquivo é baixável (ADR-0019).** Resolver a granularidade no índice e esquecer o objeto original é pior que não ter a funcionalidade: dá sensação de controle. Invariante obrigatória: **`documentos.visibilidade` é o piso** — no máximo tão permissiva quanto sua página mais restritiva — garantida por trigger nas duas direções (ao classificar página e ao afrouxar documento). Ordem de permissividade: `conselho < restrito < autenticado < publico`; **`restrito` é mais permissivo que `conselho`** apesar do nome, e inverter os dois deixa página de conselho sair pelo arquivo de uma unidade.
- **Predicado de autorização deve ser local (ADR-0023).** O valor pode depender da linha avaliada, das linhas que a definem por chave estrangeira e do sujeito da sessão — de mais nada. Quando depende de outras linhas, **toda escrita naquelas linhas é uma mudança de autorização**, ainda que ninguém a tenha chamado assim: foi um `DELETE` numa página que abriu sozinhas outras duas. `exists`/`count`/`min` dentro de função chamada por policy é sinal de alerta — exige classificar a dependência como *constitutiva* (as outras linhas **são** a decisão: `papeis`, `vinculos`, `documento_unidades`) ou *modal* (só decidem como a regra se aplica). Modal é a espécie que vaza, e a primeira pergunta é como eliminá-la. **Nunca monotonizar predicado constitutivo** — mandato que não expira contraria o veto do `juridico-lgpd` de que o acesso cessa em `vinculos.fim` + 0 dias.
- **Redundância só é defesa quando é local.** Camada de proteção redundante que introduz dependência não-local não é proteção extra, é superfície extra — foi exatamente o que vazou na 3ª rodada.
- **Invariante entre duas tabelas exige guarda nos dois lados (ADR-0021)**, e o artefato que garante isso é `docs/invariantes/` — formulário com células, vocabulário fechado e gate de CI, não regra escrita. Validar a escrita de um lado e não revalidar quando o outro muda foi a causa de três vazamentos independentes. `CHECK` é de uma linha só; assim que a invariante atravessa tabelas, a completude da guarda vira enumeração manual — e humano enumera o caminho que está escrevendo agora. Regra: antes de escrever o trigger, monte a **matriz de caminhos de violação** `(tabela × operação)`, mais os caminhos não-DML (escrita por `service_role`, restore, propriedade assumida por leitor). Célula vazia é bug. E `seq` dá **ordem, não endereço**: "a linha anterior" se pede por ordenação, nunca por `seq - 1` — sequência não promete contiguidade.
- **Falha irreversível se torna impossível, não documentada (ADR-0022).** O último `editor` vigente não pode ser desativado: com editora única (D4), um `UPDATE` de uma linha fecharia o sistema para sempre, com o acervo dentro. Mesmo princípio da D9.
- **Trava de segurança não pode depender de flag marcada à mão.** `tem_paginas_mistas` era autoral; quando não era marcada, a trava de fronteira de chunk não rodava e o chunk vazava pela busca, sem login. Agora é derivada por trigger, e a trava de chunk roda sempre que houver override no intervalo — não "quando a flag estiver ligada". Mesma lição de §5.3: regra de proteção avaliada sobre o fato, nunca sobre uma marcação que alguém precisa lembrar de fazer.
- **`REVOKE` de coluna não esconde coluna (ADR-0017).** `REVOKE SELECT (col) ON tabela FROM role` **não subtrai** de um `GRANT SELECT ON tabela`: ACL de tabela e de coluna são união, em qualquer ordem. O comando não falha, não avisa e não tem efeito — foi a chegada mais perto que o projeto esteve de expor `cpf_enc` a todo autenticado. A única forma real de excluir coluna é nunca conceder `SELECT` de tabela inteira e usar `GRANT SELECT (lista)`. Consequência aceita: coluna nova fica invisível até entrar na lista.
- **Anexos financeiros** em bucket próprio, acesso só por signed URL de TTL curto (60–300s) gerada no servidor após checagem de papel. Nunca embutida em página cacheada na CDN.
- **Trilha imutável:** triggers `SECURITY DEFINER` gravam em `audit.log`; encadeamento `hash_registro = sha256(hash_anterior || linha canônica)`; âncora semanal do hash-topo enviada por e-mail ao conselho. Assim, adulteração por quem tem acesso ao banco — inclusive a `editor` — fica detectável. Isso é o que dá ao produto autoridade perante os moradores: nem quem opera o sistema pode reescrever o passado sem deixar rastro. Três exigências de implementação que não são detalhe: (a) o trigger toma `pg_advisory_xact_lock` **antes** de ler o último hash — sem isso, duas transações concorrentes leem o mesmo `hash_anterior` e a cadeia bifurca, falha que só aparece sob carga e destrói a garantia em silêncio; (b) a serialização canônica é parte do contrato e está fixada em `docs/schema.md` — mudá-la quebra a cadeia; (c) o trigger **redige** colunas sensíveis (`cpf_enc`) em `antes`/`depois`, senão a trilha vira uma segunda cópia irremovível de dado pessoal.
- **Trilha ≠ log de acesso.** `audit.log` registra **mutação**: encadeado, append-only, permanente. `audit.acesso` registra **leitura de dado sensível** (CPF em claro, inadimplência nominal, anexo financeiro, export): sem encadeamento e expurgável em 6 meses. São duas tabelas porque retenção curta e cadeia de hash são incompatíveis — misturá-las obrigaria a escolher entre violar a retenção e quebrar a cadeia.
- **Base legal LGPD:** obrigação legal e legítimo interesse (dever de prestar contas do síndico, **Código Civil art. 1.348, VIII** — confirmado em fonte primária), **não** consentimento. Minimização: CPF em claro visível apenas ao `editor`; para o `conselho`, sempre mascarado.
- **Inadimplência nominal jamais é exposta a moradores.** Morador vê apenas a própria unidade.
- **Visibilidade pública:** por padrão, apenas convenção e regimento (normativos e impessoais). Ata e balancete exigem autenticação — contêm nome, unidade e às vezes CPF. Se a decisão for publicar acervo aberto, é obrigatória etapa de redação/anonimização antes da publicação. *Ver decisão pendente nº1 no briefing.*
- **Retenção:** piso legal de 5 anos vem da **Lei 4.591/64, art. 22, §1º, alínea "g"** — único piso explícito de guarda documental condominial, que sobreviveu à derrogação pelo Código Civil. Atas, convenção e laudos permanentes por **decisão de produto**, não por obrigação legal comprovada. Log de acesso (`audit.acesso`) 6 meses; `audit.log` é permanente e não é expurgável. Guarda de folha, ponto e registro de empregados: `[NÃO CONFIRMADO — verificar]`. Atenção: a Lei 8.212/91 art. 32, §11 **não diz mais "dez anos"** desde a Lei 11.941/2009 — hoje é "até que ocorra a prescrição"; quase toda fonte secundária de contabilidade ainda repete os 10 anos. Rotina de anonimização de ex-morador preserva agregados e apaga PII — **com uma lista fechada do que nunca se anonimiza** (`docs/juridico/off-boarding-ex-morador.md` §4): parecer e seus signatários, nome em ata/deliberação/voto, lançamentos e cobranças do período, e `audit.log`. A assinatura de parecer é preservada por **snapshot congelado** em `parecer_signatarios`, não por exceção na rotina — regra que depende de alguém verificar antes de rodar não é regra, é intenção (ADR-0020).
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

**F0 — Fundação:** repo, ambientes, schema, RLS + testes de policy, ~~auth~~, design tokens.
**F1 — Acervo:** **autenticação**, upload, pipeline de ingestão, backfill do histórico, busca híbrida, leitor de documento.

> **Correção, 2026-09-06 (ADR-0029).** F0 fechou com o schema e a RLS que *dependem* do JWT
> (`aal2`, `papeis`, `vinculos`), mas **sem uma linha de código de autenticação** — a suíte pgTAP
> simula o claim `aal` no token de teste. Auth passa a ser o primeiro corte de F1, antes de
> qualquer tela de acervo, por três razões: é o que fecha a dívida **D1** (o GoTrue emite `aal2`
> só depois da verificação do TOTP, ou já no enrolamento?), sem sessão nenhuma visibilidade
> autenticada é testável ponta a ponta, e `service_role` **não tem `INSERT` em `documentos`** por
> desenho — então nem o script de backfill roda sem uma editora autenticada.

**F2 — Financeiro:** plano de contas, importação assistida do balancete, painel para leigos, orçado vs realizado.
**F3 — Fiscalização:** motor de alertas, questionamentos, parecer do conselho, trilha auditável exposta.
**F4 — Endurecimento:** acessibilidade, QA E2E, backup e restore testado, onboarding dos moradores.

Fim de F1 já é um produto útil sozinho. Não avançar para F2 antes de o acervo estar de fato em uso.
