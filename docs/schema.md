# Breeze — Desenho do schema

**O que este documento é:** o desenho completo do modelo de dados, em DDL comentado, pronto para
o `eng-supabase` materializar na migração-baseline (`<timestamp>_00_baseline.sql`) e nas
migrações incrementais das fases seguintes.

**O que este documento não é:** não é a migração, e **não contém `CREATE POLICY`**. Cada tabela
traz um bloco `-- RLS —` dizendo qual regra ela exige e por quê; a materialização das policies é
do `eng-supabase`, e o teste pgTAP é do `auditor-rls`. Onde há predicado escrito, é **intenção**,
não texto final.

**Fonte:** SPEC §1, §2, §2.1, §3, §4, §5, §7; `docs/04-DECISOES.md` D2/D3/D4;
skills `condominio-documentos` e `condominio-plano-de-contas`.
Decisões que governam este desenho: ADR-0010 (dinheiro), ADR-0011 (estorno), ADR-0012 (RLS),
ADR-0013 (auditoria), ADR-0014 (CPF), ADR-0015 (enum vs. domínio).

> Itens marcados **[ADR-0016]** implementam correções ao SPEC §2/§2.1 **aprovadas** pelo
> orquestrador em 2026-09-04 e já refletidas em `docs/01-SPEC.md` e em `docs/04-DECISOES.md` (D8).
> A marcação permanece como rastro de proveniência, não como pendência.

### Correções posteriores à baseline, já refletidas neste documento

| Registro | O que mudou |
|---|---|
| **D11 / ADR-0018** | Visibilidade resolvida **por página** em documento de conteúdo misto. Novas: `documentos.tem_paginas_mistas`, `documento_paginas.visibilidade`, `app.nivel_visivel`, `app.nivel_efetivo`, `app.pagina_visivel`, trigger `chunks_valida_visibilidade_uniforme` |
| **D12** | Alerta "fundo sem ata" passa a se avaliar sobre `lancamentos.fundo`. **Removidas** `contas.fundo`, `contas.exige_deliberacao` e a conta de seed `2.12 Uso de fundos` |
| **ADR-0017** | `cpf_enc` excluído por `GRANT SELECT` com lista de colunas. O `REVOKE SELECT (coluna)` que este documento trazia **não bloqueava nada** |
| **D13 / ADR-0019** | **Invariante do piso:** `documentos.visibilidade` é no máximo tão permissiva quanto a página mais restritiva; override só amplia. Nova `app.ordem_visibilidade`; `tem_paginas_mistas` vira derivada; trava de chunk deixa de depender dela. Fecha V1 e V3 do `auditor-rls` |
| **D14 / ADR-0020** | `parecer_signatarios.nome_signatario` + `qualificacao`: snapshot congelado na assinatura. **Única PII denormalizada do schema**, com critério de três testes para qualquer pedido futuro por analogia |
| **D15 / ADR-0021** | **Invariante de dois lados:** toda invariante relacional exige matriz de caminhos de violação. Novo trigger em `documento_paginas` (invalida chunks ao reclassificar), novo trigger em `documentos` (piso ao afrouxar), correção do seed de `audit.verificar_cadeia` |
| **D15 / ADR-0022** | Trigger impedindo desativar a última pessoa com papel `editor` vigente |
| **D16 / ADR-0023** | **Predicado de autorização deve ser local.** Removidos `app.documento_tem_override()` e o ramo "misto" de `app.nivel_efetivo` — o nível de uma página deixa de depender de outras páginas. `tem_paginas_mistas` sai do caminho de segurança |
| **F1 / taxonomia do acervo real** (`docs/dominio/taxonomia-documental-decisoes.md`) | 5 tipos novos em `tipos_documento`: `resumo_assembleia`, `material_apoio_assembleia`, `comunicado_governanca`, `demonstrativo_cota`, `documento_construtora` (§6.1). `agi` como valor de `tipo_assembleia` já estava na baseline (§3, correção do orquestrador em 2026-09-04) — só documentado aqui agora. Dois triggers novos: `demonstrativo_cota`/`comunicado` vinculado a uma unidade em `documento_unidades` exige `documentos.visibilidade='restrito'`, nos dois lados (§6.3); `deliberacoes.documento_id` só ancora em `ata_assembleia`, nunca em `resumo_assembleia` (§7.2). Migrações `20260906090000`/`20260906090100`; testado em `supabase/tests/06_taxonomia_f1_restricao_unidade.sql` (176→202 asserts) |

> **Antes de escrever trigger de invariante que atravessa duas tabelas, leia o ADR-0021** — e
> **preencha o formulário em [`invariantes/`](invariantes/README.md)**, que tem gate de CI.
> A pergunta não é "como garanto isto aqui", é **"quais são todos os caminhos que podem violar
> isto"**, e as linhas da matriz são **geradas pelo conjunto de dependência**, não imaginadas —
> foi assim que o V10 perdeu três caminhos e o preenchimento achou um quarto.
>
> **Antes de escrever função chamada por policy, leia o ADR-0023.** `exists`, `count`, `min` ou
> `max` sobre linhas que não são a avaliada é sinal de alerta: toda escrita naquelas linhas vira
> uma mudança de autorização que ninguém percebeu ter feito.

> **Antes de denormalizar qualquer dado pessoal, leia o critério do ADR-0020.** Exige os três
> testes: o dado é elemento do ato (não conveniência); há base legal nomeável que impede eliminar;
> e o valor certo é o do momento do ato. Qualquer "não" ⇒ FK para `pessoas`.

> As migrações de D11 e ADR-0017 já estão aplicadas. O diff de D12 está com o `eng-supabase`,
> a aplicar depois do veredito do `auditor-rls` — este documento já reflete o estado final.

### Pendências históricas (resolvidas)

Registradas aqui na baseline e depois respondidas pela dona do projeto: recuperação de acesso da
editora única (**D9** — códigos impressos guardados fora de casa, contenção operacional; `papeis`
já suportava N editores sem migração) e profundidade do histórico (**D10** — condomínio entregue
em dez/2025, nove meses de série; `tipos_alerta.requer_historico_meses` fez o motor se ajustar
por dado, sem migração). O texto abaixo é mantido como registro do desenho que as acomodou.

Ambas são decisão da dona do projeto, **fora do escopo do arquiteto**, e nenhuma delas muda o
schema — é isso que as torna seguras de adiar:

**(a) Quantos `editor` no dia 1, e recuperação de acesso se a `editor` única perder o TOTP.**
`papeis` já é N:N com mandato datado: um segundo `editor` é um `INSERT`, e revogar é preencher
`mandato_fim`. Nenhuma coluna muda com qualquer das respostas. O que **não** é resolvível por
schema, e por isso precisa de resposta: com uma editora só, perder o segundo fator não tem
recuperação por outro editor. A contenção é operacional — código de recuperação impresso,
guardado fora do sistema, mais runbook. `[PENDENTE — dona do projeto]`

**(b) Profundidade do histórico / condomínio recém-entregue.** As regras "variação atípica"
(média móvel de 6 meses) e "fracionamento suspeito" precisam de série que talvez não exista.
Acomodado por `tipos_alerta.requer_historico_meses` e pela chave
`configuracoes.condominio_data_instalacao`: o motor não avalia a regra enquanto o histórico não
alcança o mínimo, e a UI mostra "aguardando histórico" em vez de silenciar. Regra sem base
produz falso positivo em série, e painel de alerta com falso positivo vira ruído ignorado —
que é o modo como este diferencial morre. Qualquer resposta cabe sem migração destrutiva.
`[PENDENTE — dona do projeto]`

## Convenções

| Convenção | Regra |
|---|---|
| Chave primária | `id uuid primary key default gen_random_uuid()` — exceto tabelas de domínio (PK textual) e log (identidade) |
| Dinheiro | `bigint`, centavos, sufixo `_centavos` obrigatório (ADR-0010) |
| Tempo | `timestamptz` sempre; `date` para competência e vigência |
| Competência | `date` truncada no dia 1 do mês, com `CHECK` |
| Nomes | `snake_case`, tabela no plural, FK `<entidade>_id` |
| Auditoria de linha | `criado_em`, `criado_por`, `atualizado_em`, `atualizado_por` nas tabelas de escrita humana |
| Exclusão | `on delete restrict` como padrão. `cascade` só para dado derivado (páginas, chunks) |
| Fase | cada tabela marca a fase em que passa a ser usada; **a baseline cria as de F0 e F1** |

---

## 1. Extensões, schemas e superfície exposta

```sql
-- Extensões. A ausência de qualquer uma deve quebrar a migração cedo e alto (ADR-0008).
create extension if not exists pgcrypto  with schema extensions;  -- gen_random_uuid, digest, hmac
create extension if not exists vector    with schema extensions;  -- pgvector (ADR-0005)
create extension if not exists unaccent  with schema extensions;  -- config pt_br (ADR-0005)
create extension if not exists pg_trgm   with schema extensions;  -- erro de digitação em nome próprio
create extension if not exists btree_gist with schema extensions; -- exclusão de período sobreposto
-- pgtap: SOMENTE em local e CI, nunca em produção. Fica em migração separada,
-- ou é criada pelo runner de teste. Não entra na baseline.

-- Schemas.
create schema if not exists app;    -- funções auxiliares de autorização (ADR-0012)
create schema if not exists audit;  -- trilha imutável (ADR-0013)
create schema if not exists job;    -- fila de processamento (ADR-0007)

-- Superfície exposta pelo PostgREST: SOMENTE public (+ storage e graphql_public do Supabase).
-- `app`, `audit` e `job` NUNCA entram em db.exposed_schemas no config.toml.
revoke all on schema app,  audit, job from public, anon, authenticated;
grant usage on schema app to authenticated;  -- só USAGE; EXECUTE é concedido função a função
```

**Higiene de privilégio (roda no fim da baseline, e é repetida em toda migração que cria tabela):**

```sql
-- Nada é acessível por padrão. Cada GRANT é explícito, por tabela e por operação.
alter default privileges in schema public revoke all on tables    from anon, authenticated;
alter default privileges in schema public revoke all on sequences from anon, authenticated;
alter default privileges in schema public revoke all on functions from anon, authenticated;
revoke all on all tables in schema public from anon, authenticated;
```

---

## 2. Configuração de busca textual PT-BR

Precisa existir **antes** de qualquer coluna gerada que a use (ADR-0005).

```sql
-- unaccent encadeado antes do stemmer português: resolve "sindico" == "síndico".
create text search configuration public.pt_br ( copy = portuguese );

alter text search configuration public.pt_br
  alter mapping for hword, hword_part, word
  with unaccent, portuguese_stem;

-- ATENÇÃO (trava de migração, não detalhe):
--   to_tsvector('public.pt_br', txt)  -> IMMUTABLE  -> pode ir em coluna gerada
--   to_tsvector(txt)                  -> STABLE     -> NÃO pode (lê default_text_search_config)
-- Sempre a forma de dois argumentos, com o nome QUALIFICADO pelo schema.

-- unaccent() de 1 argumento também é STABLE. Para normalizar termo em coluna gerada,
-- usar a forma de 2 argumentos, que é IMMUTABLE:
create or replace function public.unaccent_imutavel(txt text)
returns text language sql immutable strict parallel safe as $$
  select extensions.unaccent('extensions.unaccent'::regdictionary, txt)
$$;
```

---

## 3. Tipos enumerados (ADR-0015)

```sql
-- Papel: TRÊS valores. sindico_terceirizado NÃO é papel de conta (D3, ADR-0016 item 4).
create type public.papel as enum ('editor', 'conselho', 'morador');

create type public.visibilidade_documento as enum (
  'publico',      -- só convenção e regimento (Briefing §7.1, SPEC §7)
  'autenticado',  -- qualquer morador logado
  'conselho',     -- conselho + editor
  'restrito'      -- conselho + editor + a unidade diretamente referida
);

create type public.status_documento as enum (
  'pendente',     -- linha criada, arquivo pode nem ter chegado
  'processando',  -- worker segurou o job
  'indexado',     -- texto extraído, chunks e embeddings prontos
  'em_revisao',   -- classificação proposta, aguardando confirmação humana (SPEC §3.5)
  'publicado',    -- visível conforme `visibilidade`
  'erro'
);
-- "Rascunho" não é status: é qualquer status <> 'publicado'. Nada chega ao morador
-- sem publicação explícita (SPEC §6.1) — a RLS do morador exige status = 'publicado'.

create type public.natureza_conta   as enum ('receita', 'despesa');
create type public.tipo_lancamento  as enum ('receita', 'despesa');
create type public.fundo            as enum ('nenhum', 'reserva', 'obras');
create type public.origem_lancamento as enum ('balancete_importado', 'manual', 'ajuste');
create type public.status_cobranca  as enum ('aberta','paga','atrasada','acordo','cancelada');
create type public.tipo_vinculo     as enum ('proprietario','inquilino','residente','procurador');
create type public.severidade_alerta as enum ('baixa','media','alta','critica');
create type public.status_alerta    as enum ('aberto','em_analise','resolvido','ignorado');
create type public.status_questionamento as enum ('aberto','respondido','resolvido');
-- 'agi' (Assembleia Geral de Instalação) já na baseline (correção do orquestrador, 2026-09-04,
-- docs/inventario-acervo.md #2: a primeira ata do condomínio é uma AGI). Confirmado e não
-- reintroduzido pela taxonomia F1 (docs/dominio/taxonomia-documental-decisoes.md §2) — a
-- espécie de assembleia é propriedade de `assembleias.tipo`, não do tipo de documento.
create type public.tipo_assembleia  as enum ('ago','age','agi','conselho_fiscal');
create type public.status_job       as enum ('pendente','processando','concluido','erro','morto');
```

---

## 4. Funções auxiliares de autorização (schema `app`)

São a **fonte única** de toda regra de acesso (ADR-0012). Todas `security definer`, `stable`,
com `search_path` fixo e referências qualificadas — `security definer` sem `search_path` é
escalada de privilégio.

```sql
-- Pessoa correspondente à sessão atual. NULL para anônimo.
create or replace function app.pessoa_atual()
returns uuid language sql stable security definer set search_path = '' as $$
  select p.id from public.pessoas p
   where p.auth_user_id = auth.uid() and p.ativa
$$;

-- PRIMITIVA de RLS. Papel vale se: mandato vigente E, para editor/conselho, sessão em AAL2.
-- Papel é DADO (tabela papeis), não claim do JWT: mandato que termina hoje deixa de valer hoje.
create or replace function app.tem_papel(p public.papel)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1
      from public.papeis pa
      join public.pessoas pe on pe.id = pa.pessoa_id
     where pe.auth_user_id = auth.uid()
       and pe.ativa
       and pa.papel = p
       and pa.mandato_inicio <= current_date
       and (pa.mandato_fim is null or pa.mandato_fim >= current_date)
       -- TOTP obrigatório para papel privilegiado (ADR-0003 item 5):
       and ( p = 'morador'
             or coalesce(auth.jwt() ->> 'aal', 'aal1') = 'aal2' )
  )
$$;

create or replace function app.eh_editor()  returns boolean
  language sql stable as $$ select app.tem_papel('editor') $$;

create or replace function app.eh_gestao()  returns boolean  -- conselho OU editor
  language sql stable as $$ select app.tem_papel('conselho') or app.tem_papel('editor') $$;

create or replace function app.eh_autenticado() returns boolean
  language sql stable as $$ select app.pessoa_atual() is not null $$;

-- Papel mais forte vigente. Para UI e para o SPEC §7 ("helper papel_atual").
-- NÃO é a primitiva de RLS — policy usa tem_papel/eh_gestao.
create or replace function app.papel_atual()
returns public.papel language sql stable as $$
  select case when app.tem_papel('editor')   then 'editor'::public.papel
              when app.tem_papel('conselho') then 'conselho'::public.papel
              when app.tem_papel('morador')  then 'morador'::public.papel
         end
$$;

-- Unidades da pessoa logada, por vínculo vigente.
create or replace function app.unidades_da_pessoa()
returns setof uuid language sql stable security definer set search_path = '' as $$
  select v.unidade_id
    from public.vinculos v
   where v.pessoa_id = app.pessoa_atual()
     and v.inicio <= current_date
     and (v.fim is null or v.fim >= current_date)
$$;

-- ****************************************************************************
-- FUNÇÕES CRÍTICAS — ARMADILHA Nº 1 DO PROJETO (SPEC §7, §8.1).
-- Regra de visibilidade em UM lugar só — em DUAS CAMADAS desde a correção de 2026-09-04
-- (ADR-0018, D11), porque um PDF pode conter mais de um nível de exposição:
--
--   app.nivel_visivel(nivel, documento_id)   NÚCLEO ÚNICO do mapeamento nível → papel.
--                                            Nada mais no schema reescreve isto.
--   app.nivel_efetivo(documento_id, pagina)  qual É o nível desta página (override + herança).
--   app.documento_visivel(documento_id)      ENTRADA para o arquivo/linha inteiro.
--   app.pagina_visivel(documento_id, pagina) ENTRADA para conteúdo por página.
--
-- Nenhuma policy reescreve o predicado: todas chamam uma das duas ENTRADAS.
-- ****************************************************************************

-- ORDEM TOTAL DE PERMISSIVIDADE (ADR-0019). NÃO é a que os nomes sugerem:
--   conselho (0, mais restritivo) < restrito (1) < autenticado (2) < publico (3)
-- `restrito` é MAIS PERMISSIVO que `conselho` porque ACRESCENTA a unidade vinculada à gestão:
--   audiência(conselho) = gestão  ⊆  audiência(restrito) = gestão ∪ unidades vinculadas.
-- Inverter esses dois permitiria página 'conselho' dentro de documento 'restrito', e o arquivo —
-- baixável pelos moradores da unidade — entregaria a página do conselho. Leak de uma linha, num
-- ponto onde o nome do enum empurra ativamente para o erro.
create or replace function app.ordem_visibilidade(n public.visibilidade_documento)
returns int language sql immutable as $$
  select case n when 'conselho' then 0 when 'restrito' then 1
                when 'autenticado' then 2 when 'publico' then 3 end
$$;

-- Dado um nível já resolvido, este papel enxerga? NULL cai no ELSE => false (falha fechado).
-- [ADR-0023] O ramo "documento misto" que produzia NULL FOI REMOVIDO de nivel_efetivo — ver abaixo.
create or replace function app.nivel_visivel(p_nivel public.visibilidade_documento, p_documento_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select case p_nivel
    when 'publico'     then true
    when 'autenticado' then app.eh_autenticado()
    when 'conselho'    then app.eh_gestao()
    when 'restrito'    then app.eh_gestao() or exists (
                               select 1 from public.documento_unidades du
                                where du.documento_id = p_documento_id
                                  and du.unidade_id in (select app.unidades_da_pessoa()))
    else false
  end
$$;

-- Nível efetivo de UMA página: override explícito da própria página, ou herança do piso do
-- documento. **PREDICADO LOCAL** (ADR-0023): lê a linha avaliada e o documento dela. Mais nada.
--
-- [ADR-0023 / D16] Removido o ramo "se o documento tem override em ALGUMA página, então página sem
-- classificação não herda nada", junto com a função app.documento_tem_override().
-- Por quê: era NÃO-LOCAL — o nível da página 5 dependia do que existia na página 3. Medido pelo
-- auditor na 3ª rodada: apagar a página 3 fazia 5 e 6 passarem de invisíveis a `publico`.
-- CONTEÚDO FECHADO ABRINDO SOZINHO POR CAUSA DE UM DELETE EM OUTRA LINHA.
-- A anomalia era simétrica: sob a invariante do piso, num documento `publico` o único override
-- possível é `publico` (no-op) — e marcá-lo FECHAVA todas as demais páginas.
-- E o ramo não protegia nada: com o piso garantido (ADR-0019), `documentos.visibilidade` É o nível
-- mais restritivo do documento, logo herdá-lo é seguro por construção. Era redundância — e
-- redundância que introduz dependência não-local não é proteção extra, é superfície extra.
create or replace function app.nivel_efetivo(p_documento_id uuid, p_pagina int)
returns public.visibilidade_documento language sql stable security definer set search_path = '' as $$
  select coalesce(dp.visibilidade, d.visibilidade)
    from public.documentos d
    left join public.documento_paginas dp
      on dp.documento_id = d.id and dp.pagina = p_pagina
   where d.id = p_documento_id
$$;
-- DEPENDÊNCIA CRÍTICA E EXPLÍCITA: esta função só é segura enquanto a invariante do piso valer.
-- Aceito, e melhor que a alternativa: a dependência vira UMA invariante nomeada, testada e com
-- matriz de caminhos (docs/invariantes/INV-03), em vez de um ramo defensivo que ninguém sabia
-- enumerar. Dependência explícita e testada > defesa implícita.
--
-- `documentos.tem_paginas_mistas` permanece SÓ como sinalizador de intenção da curadoria para a
-- UI. NÃO participa de nenhuma decisão de segurança — nem por OR.

-- ENTRADA 1 — arquivo/linha inteiro. Usada por: documentos, storage.objects do bucket
-- 'documentos'. O PDF cru NÃO é fatiado: baixar o arquivo inteiro continua governado pelo nível
-- do DOCUMENTO. Anônimo não baixa a ata de 36 páginas só porque 12 delas são públicas.
create or replace function app.documento_visivel(p_documento_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.documentos d
     where d.id = p_documento_id
       and (
         app.eh_gestao()  -- gestão vê tudo, publicado ou não (conferência e curadoria)
         or (d.status = 'publicado' and app.nivel_visivel(d.visibilidade, d.id))
       )
  )
$$;

-- ENTRADA 2 — conteúdo POR PÁGINA. Usada por: documento_paginas, chunks (pela pagina_ini),
-- deliberacoes (pela pagina). É a granularidade que o texto extraído, a busca e a citação exigem.
create or replace function app.pagina_visivel(p_documento_id uuid, p_pagina int)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.documentos d
     where d.id = p_documento_id
       and (
         app.eh_gestao()
         or (d.status = 'publicado' and app.nivel_visivel(app.nivel_efetivo(d.id, p_pagina), d.id))
       )
  )
$$;

revoke all on all functions in schema app from public, anon, authenticated;
grant execute on function
  app.pessoa_atual(), app.tem_papel(public.papel), app.eh_editor(), app.eh_gestao(),
  app.eh_autenticado(), app.papel_atual(), app.unidades_da_pessoa(),
  app.nivel_visivel(public.visibilidade_documento, uuid), app.nivel_efetivo(uuid, int),
  app.documento_visivel(uuid), app.pagina_visivel(uuid, int)
to authenticated;
-- As duas ENTRADAS também precisam de EXECUTE para `anon`: documento público sem login, e
-- página pública dentro de documento não-público (o regimento embutido na ata).
grant execute on function
  app.documento_visivel(uuid), app.pagina_visivel(uuid, int),
  app.eh_gestao(), app.eh_autenticado()
to anon;
```

> **Escolher a entrada errada é a armadilha nº1 numa forma mais sutil.** `documento_visivel` onde
> cabia `pagina_visivel` publica a página da ata junto com a do regimento. A tabela abaixo é
> normativa; o `auditor-rls` testa as duas.
>
> | Objeto | Entrada correta |
> |---|---|
> | `documentos`, `storage.objects` (bucket `documentos`) | `app.documento_visivel(id)` |
> | `documento_paginas`, `chunks`, `deliberacoes` | `app.pagina_visivel(documento_id, pagina)` |

> **Correção 2026-09-06 (F1 corte C2) — exceção à linha `documentos` da tabela acima.** A policy
> de SELECT de `documentos` (§6.2) **deixou de chamar `app.documento_visivel(id)`** e passou a
> avaliar o predicado **inline, local à própria linha**:
> `app.eh_gestao() or (status = 'publicado' and app.nivel_visivel(visibilidade, id))`.
> Motivo: `app.documento_visivel` reconsulta `public.documentos` — e uma policy de SELECT sobre
> `documentos` que reconsulta `documentos` nega `INSERT ... RETURNING` e `UPDATE ... RETURNING`
> para QUALQUER papel, inclusive editor com `aal2`: sob MVCC, a subconsulta disparada pelo mesmo
> comando não enxerga a linha que esse comando está inserindo/alterando (cid da linha nova ==
> cid do comando corrente), então o `exists` dá falso e a policy nega — mesmo a linha sendo,
> segundos depois, plenamente visível a um `select` num comando novo. É a espécie MODAL do
> ADR-0023 ("predicado de autorização deve ser local"): a releitura não protegia nada (`status`,
> `visibilidade` e `id` já estavam na própria linha), só introduzia a não-localidade que quebrou
> RETURNING. `app.documento_visivel(uuid)` **continua existindo, sem alteração de corpo**, e
> continua sendo a entrada certa para quem pergunta de FORA de `documentos` — `storage.objects`
> é o único chamador restante hoje. Alcance de autorização idêntico ao de antes: só a forma
> mudou. Migração: `supabase/migrations/20260906100500_documentos_select_predicado_local.sql`.
> Varredura da mesma classe feita nesta correção (comentário completo na migração): nenhuma outra
> policy do schema tem o mesmo defeito — `documento_paginas`/`chunks` só são escritas por
> `service_role` (que ignora RLS por completo, então RETURNING nunca passa pela policy);
> `pessoas`/`papeis` reconsultam a própria tabela dentro de uma função chamada pelo `or`, mas o
> outro operando do `or` já é local e cobre exatamente o caso em que a escrita afeta a própria
> linha da sessão — não há caminho onde o resultado observável mude.

### A INVARIANTE DO PISO (ADR-0019) — sem ela, tudo acima é ilusório

```
Para toda página p de um documento d:   ordem(d.visibilidade) <= ordem(p.visibilidade)
```

`documentos.visibilidade` é o **piso**: o arquivo é no mínimo tão restrito quanto sua página mais
sensível. **Override de página só amplia o alcance do texto derivado; nunca o reduz.**

Por que isto existe (achado **V3** do `auditor-rls`,
`supabase/tests/01_visibilidade_documento_pagina_chunk_rls.sql`): num documento `publico` com uma
página `conselho`, o texto da página era corretamente negado em `documento_paginas` e `chunks`
**e o PDF inteiro era baixável por anônimo** — a policy do bucket faz o gate por
`app.documento_visivel`. A granularidade foi resolvida no índice e esquecida no objeto original.
Um PDF é atômico: quem o baixa leva tudo.

`<=` e não `=`: documento mais restrito que todas as suas páginas é seguro (excesso de zelo) e fica
permitido. Proibido é o documento mais permissivo que qualquer página sua.

Triggers nas **duas** direções — validar só um lado deixa a porta aberta pelo outro:

```sql
-- documento_paginas BEFORE INSERT/UPDATE OF visibilidade:
--   rejeita se ordem(NEW.visibilidade) < ordem(documento.visibilidade).
--   Mensagem acionável: "baixe documentos.visibilidade para <nível> antes de marcar esta página".
-- documentos BEFORE UPDATE OF visibilidade:
--   rejeita se ordem(NEW.visibilidade) > min(ordem(pagina.visibilidade)) das páginas classificadas.
```

> **ACHADO V3-R — e a lição de método que vale mais que o conserto.** Este bloco já dizia "nas duas
> direções" desde o ADR-0019. A implementação fez **uma**: o piso era validado ao escrever a
> página, e subir `documentos.visibilidade` depois quebrava a invariante sem ninguém checar — texto
> negado, PDF inteiro liberado.
>
> Prosa em documento de desenho não sobrevive à implementação. Por isso a matriz de caminhos do
> ADR-0021 é **célula de checklist**, não frase de parágrafo:
>
> | Caminho | Estado |
> |---|---|
> | `INSERT` em `documento_paginas` com `visibilidade` | guardado |
> | `UPDATE` de `documento_paginas.visibilidade` | guardado (piso) + invalida chunks (V1-R) |
> | `UPDATE` de `documentos.visibilidade` | **guardado (V3-R)** |
> | `INSERT` de `documentos` já mais permissivo que páginas | impossível: não há páginas ainda |
> | `DELETE` de `documento_paginas` | aceito: remover página não afrouxa o piso |
> | Escrita direta por `service_role` (worker) | aceito com motivo: o worker não escreve `visibilidade` |

**Ordem de operações na importação:** para documento que já nasce misto, define-se primeiro o nível
do documento (o piso), depois os overrides. O pipeline de F1 precisa seguir essa ordem, senão a
primeira página classificada é rejeitada.

**Quando o caso inverso aparecer** (balancete `autenticado` com página de inadimplência nominal que
precisa ser `conselho`): baixa-se `documentos.visibilidade` para `conselho` e marcam-se as demais
páginas como `autenticado`. Morador continua lendo, buscando e citando o corpo; o **PDF fica com a
gestão**, porque o PDF de fato contém a página nominal. A UI precisa explicar isso, não só esconder
o botão de download.

---

## 5. Identidade e cadastro

### 5.1 `unidades` — F0

```sql
create table public.unidades (
  id            uuid primary key default gen_random_uuid(),
  bloco         text not null default '',        -- '' quando o condomínio não tem bloco
  numero        text not null,                   -- [ADR-0016 item 10] texto: '101-A', 'Cob 02', 'Loja 1'
  ordem         int,                             -- ordenação natural; evita cast de numero
  fracao_ideal  numeric(12,9) not null check (fracao_ideal > 0 and fracao_ideal <= 1),
  area_m2       numeric(10,2) check (area_m2 > 0),
  ativa         boolean not null default true,
  criado_em     timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  constraint unidades_bloco_numero_uk unique (bloco, numero)
);
create index unidades_ordem_idx on public.unidades (bloco, ordem, numero);

comment on table public.unidades is
  'RLS: leitura para qualquer autenticado; escrita só editor. Não é dado pessoal — é a planta do
   condomínio, e todo morador precisa vê-la para entender rateio por fração ideal.';
comment on column public.unidades.fracao_ideal is
  'Fração ideal, NÃO é dinheiro (ADR-0010 item 5). A soma das frações das unidades ativas deve
   ser 1; isso é invariante verificada por teste, não por constraint de tabela.';
```

```
-- RLS — unidades
--   select : app.eh_autenticado()
--   insert/update/delete : app.eh_editor()
-- Por quê: base de rateio, pública entre condôminos, sem PII. Escrita altera o denominador de
-- todo cálculo financeiro — logo, papel único de escrita (D4) e trilha obrigatória.
```

### 5.2 `pessoas` — F0 · **tabela mais sensível do schema**

```sql
create table public.pessoas (
  id            uuid primary key default gen_random_uuid(),
  -- Única amarra a auth.users (ADR-0002). Anulável: pessoa pode existir sem conta
  -- (ex-morador preservado para histórico; morador ainda não convidado).
  auth_user_id  uuid unique references auth.users(id) on delete set null,
  nome          text not null check (length(btrim(nome)) >= 3),
  -- e-mail já normalizado em minúsculas pela aplicação; check impede o resto.
  email         text unique check (email is null or email = lower(btrim(email))),
  -- ADR-0014: HMAC-SHA256(cpf_normalizado, PEPPER) calculado NA APLICAÇÃO.
  -- O pepper nunca entra no banco. Dump sem pepper não permite lookup por CPF.
  cpf_hash      bytea unique check (cpf_hash is null or octet_length(cpf_hash) = 32),
  -- ADR-0014: nonce(12) || AES-256-GCM(cpf) || tag(16), cifrado NA APLICAÇÃO.
  cpf_enc       bytea,
  -- Exibição mascarada ao conselho: '***.***.789-**'. Guarda os dígitos 7-9.
  -- NUNCA os dígitos verificadores (deles se deriva material para reduzir busca).
  cpf_ultimos_digitos char(3) check (cpf_ultimos_digitos ~ '^[0-9]{3}$'),
  telefone      text,
  ativa         boolean not null default true,
  observacoes   text,
  criado_em     timestamptz not null default now(),
  criado_por    uuid references public.pessoas(id),
  atualizado_em timestamptz not null default now(),
  constraint pessoas_cpf_par_ck check ((cpf_hash is null) = (cpf_enc is null))
);
create index pessoas_nome_trgm_idx on public.pessoas using gin (nome gin_trgm_ops);

-- ADR-0012 item 7 / ADR-0014 item 4 — ÚNICA exceção de privilégio de coluna do schema.
-- RLS é por linha e não esconde coluna.
--
-- ARMADILHA DE POSTGRES (ADR-0017 — o desenho anterior deste documento estava ERRADO e não
-- bloqueava nada): `REVOKE SELECT (col) ON tabela FROM role` NÃO subtrai de um
-- `GRANT SELECT ON tabela` — ACL de tabela e de coluna são UNIÃO, nunca subtração, em NENHUMA
-- ordem. O comando não falha, não avisa e não tem efeito.
-- A única forma real de excluir uma coluna é nunca conceder SELECT de tabela inteira:
revoke all on public.pessoas from public, anon, authenticated;
grant select (id, auth_user_id, nome, email, cpf_hash, cpf_ultimos_digitos, telefone, ativa,
  observacoes, criado_em, criado_por, atualizado_em) on public.pessoas to authenticated;
-- cpf_enc AUSENTE da lista, por construção.
grant insert, update on public.pessoas to authenticated;  -- delete: ninguém (anonimização)
-- INSERT/UPDATE de tabela inteira permanecem, inclusive cpf_enc: é a editor cifrando e gravando.
-- Só a LEITURA de volta é vedada.
-- CONSEQUÊNCIA: coluna nova em `pessoas` fica INVISÍVEL até ser incluída neste GRANT. Falha
-- fechado — lado certo para falhar, mas toda migração que adicionar coluna aqui precisa
-- atualizar a lista no mesmo arquivo.

comment on table public.pessoas is
  'RLS: pessoa lê a PRÓPRIA linha; conselho lê todas SEM CPF; editor lê todas. Escrita só editor.
   Por quê: é o cadastro de dado pessoal do condomínio. O lookup de login por CPF acontece em
   rotina de servidor com service_role (ADR-0003) — não pela RLS, porque nesse momento não há
   sessão. CPF em claro exige decifra na aplicação + registro em audit.acesso (ADR-0014).';
```

```
-- RLS — pessoas
--   select : id = app.pessoa_atual()  OR  app.eh_gestao()
--   insert/update : app.eh_editor()
--   delete : ninguém (anonimização em vez de exclusão — SPEC §7)
-- Mascaramento do CPF para o conselho NÃO é policy: é o REVOKE de coluna acima + a UI usando
-- cpf_ultimos_digitos. Uma policy não consegue esconder coluna.
```

### 5.3 `vinculos` — F0

```sql
create table public.vinculos (
  id          uuid primary key default gen_random_uuid(),
  unidade_id  uuid not null references public.unidades(id) on delete restrict,
  pessoa_id   uuid not null references public.pessoas(id) on delete restrict,
  tipo        public.tipo_vinculo not null,
  inicio      date not null default current_date,
  fim         date,
  criado_em   timestamptz not null default now(),
  criado_por  uuid references public.pessoas(id),
  constraint vinculos_periodo_ck check (fim is null or fim >= inicio)
);
create index vinculos_unidade_fim_idx on public.vinculos (unidade_id, fim);
create index vinculos_pessoa_vigente_idx on public.vinculos (pessoa_id) where fim is null;
create unique index vinculos_vigente_uk on public.vinculos (unidade_id, pessoa_id, tipo)
  where fim is null;
-- Alternativa mais forte, se aparecer sobreposição histórica indevida (exige btree_gist):
--   exclude using gist (unidade_id with =, pessoa_id with =, tipo with =,
--                       daterange(inicio, fim, '[]') with &&)

comment on table public.vinculos is
  'RLS: pessoa vê os vínculos das PRÓPRIAS unidades; gestão vê todos; escrita só editor.
   Por quê: esta tabela É o predicado de "própria unidade" usado por cobrancas e por documento
   restrito. Vínculo errado = morador vendo dado de vizinho. Escrita aqui é evento auditado.';
```

```
-- RLS — vinculos
--   select : unidade_id in (select app.unidades_da_pessoa())  OR  app.eh_gestao()
--   insert/update/delete : app.eh_editor()
```

### 5.4 `papeis` — F0

```sql
create table public.papeis (
  id             uuid primary key default gen_random_uuid(),
  pessoa_id      uuid not null references public.pessoas(id) on delete cascade,
  papel          public.papel not null,
  mandato_inicio date not null default current_date,
  mandato_fim    date,
  concedido_por  uuid references public.pessoas(id),
  motivo         text,
  criado_em      timestamptz not null default now(),
  constraint papeis_mandato_ck check (mandato_fim is null or mandato_fim >= mandato_inicio)
);
create index papeis_pessoa_fim_idx on public.papeis (pessoa_id, mandato_fim);
create unique index papeis_vigente_uk on public.papeis (pessoa_id, papel) where mandato_fim is null;
-- Índice que app.tem_papel() percorre a cada avaliação de policy:
create index papeis_papel_vigente_idx on public.papeis (papel, mandato_inicio, mandato_fim);

-- [ADR-0022 / V10] Trigger: o ÚLTIMO `editor` vigente não pode ser desativado.
-- Não é vazamento, é indisponibilidade IRREVERSÍVEL: com editora única (D4), ela pode se
-- auto-desativar (pessoas.ativa = false) ou deixar o mandato expirar, e ninguém reverte —
-- service_role não tem UPDATE em pessoas nem papeis (ADR-0012 item 6, e isso está CERTO).
-- Guarda nos dois caminhos que produzem o mesmo estado (matriz do ADR-0021):
--   pessoas  BEFORE UPDATE OF ativa       -> rejeita se é a última pessoa com editor vigente
--   papeis   BEFORE UPDATE OF mandato_fim / BEFORE DELETE -> idem
-- A mensagem precisa DIZER A SAÍDA ("conceda `editor` a outra pessoa antes de encerrar este
-- mandato"), não só barrar — trava sem saída indicada vira contorno criativo.
-- Limite honesto: isto resolve o ACIDENTE, não o ataque. Conta comprometida continua exigindo
-- D9 (códigos de recuperação impressos) + a trilha do ADR-0013.

comment on table public.papeis is
  'RLS: pessoa lê os PRÓPRIOS papéis; gestão lê todos; escrita só editor com AAL2.
   Por quê: é a tabela que decide quem pode o quê — a raiz da autorização. Uma pessoa pode
   acumular papéis (morador + conselho); por isso a primitiva é tem_papel(), não papel_atual().
   [ADR-0016 item 3, aprovado em D8] O SPEC dizia "escrita só admin"; não existe papel admin — é
   o editor com AAL2. Corrigido no SPEC §2.
   RISCO REGISTRADO: com D4 (editor única), quem concede papel é quem já detém todos. A trilha
   encadeada (ADR-0013) é a única contenção. A tabela já suporta N editores com mandato datado,
   então a resposta à pendência (a) — quantos administradores no dia 1 — não exige migração.';
```

```
-- RLS — papeis
--   select : pessoa_id = app.pessoa_atual()  OR  app.eh_gestao()
--   insert/update : app.eh_editor()
--   delete : ninguém — encerrar mandato é preencher mandato_fim, nunca apagar a linha
```

---

## 6. Acervo documental

### 6.1 `tipos_documento` — F0 · tabela de domínio (ADR-0015)

```sql
create table public.tipos_documento (
  codigo              text primary key,         -- 'convencao','regimento','ata_assembleia',...
  nome                text not null,
  visibilidade_padrao public.visibilidade_documento not null default 'autenticado',
  -- Trava do Briefing §7.1 / SPEC §7: só normativo impessoal pode ser público.
  permite_publico     boolean not null default false,
  retencao_meses      int,                      -- null = permanente
  ordem               int not null default 100,
  ativo               boolean not null default true
);

comment on table public.tipos_documento is
  'RLS: leitura para todos (inclusive anon — a UI pública lista tipos); escrita só editor.
   Por quê: é taxonomia, não dado. Tabela de domínio (e não enum) porque a taxonomia cresce
   com a operação — laudo novo não deve exigir deploy (ADR-0015).';
```

Seed (de `condominio-documentos`; **corrigido**: vai em MIGRAÇÃO versionada
(`20260904120700_tipos_documento_seed.sql` + `20260906090000_taxonomia_f1_tipos_documento_seed.sql`),
não em `supabase/seed.sql` — é dado de referência que precisa existir em todo ambiente,
inclusive produção, e `seed.sql` só roda em `db reset` local/CI, nunca em `db push` remoto):

**14 tipos da baseline F0** (`comunicado` foi achado estrutural da sonda de acervo real de
2026-09-04, `docs/inventario-acervo.md` — 24/43 documentos sem tipo formal):

| codigo | nome | visibilidade_padrao | permite_publico | retencao |
|---|---|---|---|---|
| `convencao` | Convenção de condomínio | `publico` | **sim** | permanente |
| `regimento` | Regimento interno | `publico` | **sim** | permanente |
| `ata_assembleia` | Ata de assembleia (AGO/AGE/AGI) | `autenticado` | não | permanente |
| `edital_convocacao` | Edital de convocação | `autenticado` | não | 60 |
| `comunicado` | Comunicado avulso | `autenticado` | não | 24 |
| `balancete` | Balancete mensal | `autenticado` | não | permanente |
| `prestacao_contas` | Prestação de contas anual | `autenticado` | não | permanente |
| `previsao_orcamentaria` | Previsão orçamentária | `autenticado` | não | permanente |
| `contrato` | Contrato de fornecedor | `autenticado` | não | permanente |
| `apolice_seguro` | Apólice de seguro | `autenticado` | não | 60 |
| `laudo_tecnico` | Laudo técnico (AVCB, SPDA, elevador…) | `autenticado` | não | permanente |
| `notificacao_multa` | Notificação / multa | **`restrito`** | não | 60 |
| `documentacao_obra` | Documentação de obra | `autenticado` | não | permanente |
| `ata_conselho` | Ata do conselho fiscal | `conselho` | não | permanente |

**+5 tipos da taxonomia F1 do acervo real** (`docs/dominio/taxonomia-documental-decisoes.md`,
guardiao-dominio, sonda de 43 PDFs reais):

| codigo | nome | visibilidade_padrao | permite_publico | retencao |
|---|---|---|---|---|
| `resumo_assembleia` | Resumo de assembleia (não oficial) | `autenticado` | não | permanente |
| `material_apoio_assembleia` | Material de apoio de assembleia | `autenticado` | não | permanente |
| `comunicado_governanca` | Comunicado de governança (posse/renúncia/apresentação) | `autenticado` | não | permanente |
| `demonstrativo_cota` | Demonstrativo de composição de cota | `autenticado` ⚠ | não | permanente |
| `documento_construtora` | Documento da construtora / entrega de obra | `autenticado` | não | permanente |

> Retenção aqui informa **obrigação mínima de guarda**, nunca gatilho de expurgo
> (`condominio-documentos`, seção final).

> ⚠ **`demonstrativo_cota` e `comunicado` são condicionalmente `restrito`.** O valor de
> `visibilidade_padrao` acima é o do TIPO; um DOCUMENTO desses dois tipos vinculado a uma
> unidade específica (linha em `documento_unidades`) é forçado a `documentos.visibilidade =
> 'restrito'` por trigger — nunca por valor de seed, porque a mesma linha de tipo cobre tanto o
> demonstrativo agregado do condomínio (autenticado, todo mundo) quanto o demonstrativo nominal
> de uma unidade (restrito, só ela + gestão). Dois triggers, nos DOIS LADOS da relação
> (ADR-0021): `tg_documento_unidades_exige_restrito` (vincular unidade exige visibilidade já
> `restrito`) e `tg_documentos_bloqueia_rebaixar_restrito_vinculado` (rebaixar depois que o
> vínculo existe é rejeitado). Migração `20260906090100_taxonomia_f1_restricao_unidade_trigger.sql`;
> testado em `supabase/tests/06_taxonomia_f1_restricao_unidade.sql` — mesma régua já usada para
> `notificacao_multa`/inadimplência (dado individualizado por unidade nunca fica `autenticado`).
> `notificacao_multa` tem o mesmo risco de fundo (nada barra hoje rebaixá-la com o vínculo já
> criado) — gap pré-existente, deliberadamente fora desta rodada (linha de escopo do
> orquestrador); sinalizado para `auditor-rls` decidir se generaliza.

### 6.2 `documentos` — F0/F1

```sql
create table public.documentos (
  id             uuid primary key default gen_random_uuid(),
  tipo           text not null references public.tipos_documento(codigo) on delete restrict,
  titulo         text not null check (length(btrim(titulo)) >= 3),
  data_documento date,
  competencia    date,   -- mês de referência; sempre dia 1
  storage_bucket text not null default 'documentos',
  storage_path   text not null unique,
  -- Nome do objeto NÃO carrega informação (ADR-0004 item 5): '<uuid>.pdf'.
  -- [F1/ADR-0025] NULLABLE desde 2026-09-06: o hash é calculado NO WORKER (ADR-0004, "o cliente
  -- pode mentir"), e a linha nasce humana (estágio 0) antes de o worker ler o objeto no Storage
  -- (estágio 1, hash_dedupe). UNIQUE permanece — múltiplos NULL são permitidos; a violação de
  -- unicidade quando o hash É preenchido é a detecção de duplicata (caso de teste real: par
  -- #15/#16 do acervo, dois lembretes byte-idênticos da ata AGE de 04.02.2026).
  sha256         bytea unique check (octet_length(sha256) = 32),  -- dedupe (SPEC §3.1)
  bytes          bigint check (bytes > 0),
  paginas        int check (paginas > 0),
  ocr_aplicado   boolean not null default false,
  status         public.status_documento not null default 'pendente',
  visibilidade   public.visibilidade_documento not null default 'autenticado',
  -- [ADR-0018 / D11, revisada pelo ADR-0019 / D13] true quando o documento embute conteúdo de
  -- nível de exposição diferente do padrão — ex.: a ata AGE de 36 páginas que embute o Regimento
  -- Interno inteiro como anexo.
  --
  -- COLUNA DERIVADA, NÃO AUTORAL (achado V1 do auditor-rls): antes ela precisava ser marcada à
  -- mão, e quando não era, o trigger de fronteira de chunk simplesmente não rodava e o chunk
  -- vazava pela busca, sem login. Flag que precisa ser marcada à mão para uma trava de segurança
  -- funcionar não é trava, é convenção. Agora é um LIMITE INFERIOR mantido por trigger:
  --     tem_paginas_mistas >= exists(override em documento_paginas)
  --   * trigger em documento_paginas LIGA a flag ao surgir o primeiro override;
  --   * documentos não aceita DESLIGAR enquanto houver override;
  --   * a editor ainda pode LIGAR antes de classificar ("sei que é misto, ainda não classifiquei").
  --
  -- A semântica de "não herda por omissão" continua, por conservadorismo — mas desde a invariante
  -- do piso (ADR-0019) herdar o padrão do documento já é seguro, porque o padrão É o piso.
  tem_paginas_mistas boolean not null default false,
  versao_pipeline int not null default 1,   -- idempotência do reprocessamento (SPEC §3)
  metadados      jsonb not null default '{}'::jsonb,  -- extração da classificação (SPEC §3.5)
  -- [F1/ADR-0026, corte C4, 2026-09-06] Eixo de ESTADO DA MÁQUINA, ORTOGONAL a `status`.
  -- NULL = sem índice de busca válido para a versao_pipeline corrente. Rebaixar `status` para
  -- sinalizar isto faria o documento sumir INTEIRO da RLS do morador (que exige
  -- status='publicado') — estrago maior que o problema (ADR-0026 §3). Escrita EXCLUSIVA de três
  -- triggers (chunks_marca_indexado, chunks_invalida_documento,
  -- documentos_versao_pipeline_invalida_indexacao) — nenhum código de aplicação escreve aqui.
  -- NUNCA participa de autorização (INV-13, docs/invariantes/INV-13-...).
  indexado_em    timestamptz,
  publicado_em   timestamptz,
  publicado_por  uuid references public.pessoas(id),
  erro_detalhe   text,
  criado_em      timestamptz not null default now(),
  criado_por     uuid references public.pessoas(id),
  atualizado_em  timestamptz not null default now(),
  constraint documentos_competencia_ck check (
    competencia is null or competencia = date_trunc('month', competencia::timestamp)::date),
  constraint documentos_publicacao_ck check (
    status <> 'publicado' or (publicado_em is not null and publicado_por is not null))
);

create index documentos_tipo_data_idx     on public.documentos (tipo, data_documento desc);
create index documentos_competencia_idx   on public.documentos (competencia desc) where competencia is not null;
create index documentos_status_idx        on public.documentos (status);
-- Índice que a RLS percorre (ADR-0012: policy sem índice vira varredura por linha):
create index documentos_visibilidade_idx  on public.documentos (visibilidade, status);
create index documentos_mistos_idx        on public.documentos (id) where tem_paginas_mistas;
create index documentos_ano_idx           on public.documentos ((extract(year from coalesce(competencia, data_documento))));
create index documentos_titulo_trgm_idx   on public.documentos using gin (titulo gin_trgm_ops);
create index documentos_metadados_idx     on public.documentos using gin (metadados jsonb_path_ops);
-- [F1/ADR-0026, corte C4] Sustenta a sentinela (app.documentos_fora_da_busca, §11.2) sem varrer.
create index documentos_fora_da_busca_idx on public.documentos (id)
  where status = 'publicado' and indexado_em is null;

-- Trigger de visibilidade: 'publico' só para tipo com permite_publico.
-- Não pode ser CHECK (CHECK não faz subconsulta), e não pode ficar só na aplicação:
-- publicar ata como pública é vazamento de nome, unidade e às vezes CPF (SPEC §7).
create or replace function public.tg_documentos_valida_visibilidade()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.visibilidade = 'publico'
     and not exists (select 1 from public.tipos_documento t
                      where t.codigo = new.tipo and t.permite_publico) then
    raise exception
      'Tipo de documento % não pode ter visibilidade pública (Briefing §7.1, SPEC §7)', new.tipo;
  end if;
  return new;
end $$;
create trigger documentos_valida_visibilidade
  before insert or update of visibilidade, tipo on public.documentos
  for each row execute function public.tg_documentos_valida_visibilidade();

comment on table public.documentos is
  'RLS: TODA leitura passa por app.documento_visivel(id). Escrita só editor.
   Por quê: é a tabela-raiz da visibilidade do acervo. documento_paginas, chunks, deliberacoes e
   storage.objects espelham esta regra CHAMANDO A MESMA FUNÇÃO — nunca copiando o predicado
   (SPEC §7, armadilha nº1).';
```

```
-- RLS — documentos
--   select : app.documento_visivel(id)
--   insert/update : app.eh_editor()
--   delete : ninguém (arquivar por status, não apagar; documento é fonte de lançamento)
```

> **Correção 2026-09-06:** o `select` de `documentos` acima é o desenho ORIGINAL de F0. Desde
> `20260906100500_documentos_select_predicado_local.sql`, a policy real não chama mais
> `app.documento_visivel(id)` — ver a nota de correção logo após a tabela normativa da §4 para o
> predicado local que a substitui e o porquê (RETURNING/MVCC). `documento_paginas`, `chunks`,
> `deliberacoes` e `storage.objects` continuam espelhando via `app.pagina_visivel`/
> `app.documento_visivel` sem nenhuma mudança — a correção é só da policy que a própria
> `documentos` usa sobre si mesma.

### 6.3 `documento_unidades` — F1 · **[ADR-0016 item 7]**

```sql
-- Sem esta tabela, visibilidade 'restrito' não é avaliável e vira sinônimo de 'conselho'.
-- Caso de uso: notificação/multa é visível só à unidade notificada
-- (condominio-documentos §11), além de conselho e editor.
create table public.documento_unidades (
  documento_id uuid not null references public.documentos(id) on delete cascade,
  unidade_id   uuid not null references public.unidades(id)   on delete restrict,
  criado_em    timestamptz not null default now(),
  primary key (documento_id, unidade_id)
);
create index documento_unidades_unidade_idx on public.documento_unidades (unidade_id);

comment on table public.documento_unidades is
  'RLS: leitura para gestão e para a própria unidade; escrita só editor.
   Por quê: é o predicado que torna visibilidade=restrito implementável. A própria existência da
   linha é informação ("a unidade 302 foi notificada"), então a leitura é restrita do mesmo jeito.';
```

> **[F1]** Para `demonstrativo_cota` e `comunicado`, esta tabela é gate de ESCRITA além de
> leitura: `tg_documento_unidades_exige_restrito` (ver §6.1) rejeita o INSERT/UPDATE aqui se o
> documento referenciado ainda não é `restrito`. `notificacao_multa` não tem essa trava — a
> tabela permite o vínculo independente do tipo, como sempre permitiu.

### 6.4 `documento_paginas` — F1 · **espelha `documentos`**

```sql
create table public.documento_paginas (
  id            uuid primary key default gen_random_uuid(),
  documento_id  uuid not null references public.documentos(id) on delete cascade,
  pagina        int not null check (pagina > 0),
  texto         text,          -- texto EFETIVO (nativo ou OCR) — é dele que saem os chunks
  texto_nativo  text,          -- o que a extração nativa achou; preservado p/ diagnóstico (ADR-0006)
  fonte_texto   text not null default 'nativo'
                check (fonte_texto in ('nativo','ocr','misto','vazio')),
  confianca_ocr numeric(4,3) check (confianca_ocr between 0 and 1),  -- não é dinheiro
  rotacao       int check (rotacao in (0,90,180,270)),
  -- [F1/ADR-0024 §2] Qual MOTOR produziu `texto` — fonte_texto já diz a CLASSE (nativo/ocr/
  -- misto/vazio); sem o motor, "reprocessar só o que o motor local errou" não é uma consulta.
  -- NULL antes do estágio 2/3. Valor do tipo (não enum fechado): 'nativo' | 'vision:<versão do
  -- SO>' (Apple Vision local, motor primário) | 'api:<fornecedor>:<modelo>' (só sob gatilho
  -- nomeado G1/G2/G3, ADR-0024 §3, por documento).
  motor_texto   text check (motor_texto is null or motor_texto = 'nativo'
                             or motor_texto like 'vision:%' or motor_texto like 'api:%'),
  -- [ADR-0018 / D11] Override por página. NULL = herda documentos.visibilidade.
  -- Preenchida = sobrescreve para ESTA página: as páginas do regimento embutido na ata ganham
  -- 'publico' aqui, com a ata em 'autenticado'.
  -- [ADR-0019 / D13] O override SÓ AMPLIA: ordem(esta) >= ordem(documento). Trigger rejeita
  -- override mais restritivo que o documento — senão o texto ficaria negado na busca e o mesmo
  -- texto sairia inteiro pelo download do PDF (achado V3). Para restringir de fato, baixe primeiro
  -- documentos.visibilidade.
  -- Toda a resolução vive em app.nivel_efetivo(); nenhuma policy a reescreve.
  visibilidade  public.visibilidade_documento,
  versao_pipeline int not null default 1,
  criado_em     timestamptz not null default now(),
  constraint documento_paginas_uk unique (documento_id, pagina)
);
create index documento_paginas_documento_idx on public.documento_paginas (documento_id);

comment on table public.documento_paginas is
  'RLS: ESPELHA documentos via app.pagina_visivel(documento_id, pagina) — resolve override e
   herança de visibilidade por página (ADR-0018, D11).
   Por quê: ARMADILHA Nº1 (SPEC §7, §8.1). Esta tabela contém o texto integral do documento; RLS
   em documentos sem RLS aqui entrega o conteúdo restrito inteiro por uma consulta trivial.
   Escrita: NENHUM papel de usuário. Só o worker, por service_role — é saída de máquina.';
```

```
-- RLS — documento_paginas
--   select : app.pagina_visivel(documento_id, pagina)   <-- entrada POR PÁGINA, não documento_visivel
--   insert/update/delete : nenhuma policy (worker usa service_role, que contorna RLS por
--                          construção — ADR-0012 item 6)
-- Testes pgTAP obrigatórios:
--   1. morador NÃO lê página de documento visibilidade='conselho'
--   2. anon LÊ a página do regimento embutido (override 'publico') numa ata 'autenticado'
--   3. anon NÃO lê a página seguinte, da ata, no MESMO documento
--   4. em documento tem_paginas_mistas, página com visibilidade NULL não é lida por não-gestão
```

### 6.5 `chunks` — F1 · **espelha `documentos` — o ponto mais crítico do schema**

```sql
create table public.chunks (
  id            uuid primary key default gen_random_uuid(),
  documento_id  uuid not null references public.documentos(id) on delete cascade,
  pagina_ini    int not null check (pagina_ini > 0),
  pagina_fim    int not null,
  ordem         int not null check (ordem >= 0),
  texto         text not null,
  tokens        int,
  -- Coluna gerada: exige to_tsvector de DOIS argumentos com config qualificada (ADR-0005).
  tsv           tsvector generated always as (to_tsvector('public.pt_br', texto)) stored,
  embedding     extensions.vector(1536),
  -- [F1/ADR-0027] Versão do MODELO de embedding — independente de versao_pipeline, que muda só
  -- com texto/fronteira de chunk. NULL = sem embedding (estado de todo chunk em F1, etapa
  -- desligada por falta de chave de LLM). Trocar de modelo bumpa só este campo.
  versao_embedding smallint,
  -- [F1/SPEC §4, D17 — "medida ao chunkizar o Regimento real"] Rótulo de seção/capítulo vigente
  -- onde o chunk começa. NULL quando o documento não tem hierarquia de seção conhecida (ata,
  -- balancete, edital). Existe porque numeração de artigo NÃO é globalmente única em documento
  -- real: o Regimento Interno reinicia a numeração a cada capítulo (24 capítulos, 24 "Artigo
  -- 1º" distintos) — sem capítulo, "Artigo 5º" não identifica nada. O chunker garante que
  -- nenhum chunk atravessa fronteira de seção (mesma disciplina de fronteira dura já usada para
  -- visibilidade). Texto livre, é rótulo de citação — não participa de RLS.
  secao         text,
  versao_pipeline int not null default 1,
  criado_em     timestamptz not null default now(),
  constraint chunks_paginas_ck check (pagina_fim >= pagina_ini),
  constraint chunks_uk unique (documento_id, versao_pipeline, ordem)
);

create index chunks_tsv_idx        on public.chunks using gin (tsv);
create index chunks_documento_idx  on public.chunks (documento_id);
create index chunks_texto_trgm_idx on public.chunks using gin (texto gin_trgm_ops);
-- HNSW SÓ ACIMA DE ~10k LINHAS (ADR-0005). Abaixo disso, varredura é mais rápida e mais exata.
-- Deixar comentado na baseline; virar migração própria quando o acervo justificar:
-- create index chunks_embedding_idx on public.chunks
--   using hnsw (embedding extensions.vector_cosine_ops) with (m = 16, ef_construction = 64);

comment on table public.chunks is
  'RLS: ESPELHA documentos via app.pagina_visivel(documento_id, pagina_ini) — a página inicial do
   trecho é a âncora de visibilidade (ADR-0018, D11).
   Por quê: ESTA É A ARMADILHA Nº1 (SPEC §7, §8.1, Risco §8.1). A busca lê chunks. RLS em
   documentos sem RLS aqui faz o motor de busca vazar trecho de documento restrito para qualquer
   morador — e vaza pela funcionalidade central do produto, com o texto já destacado.
   A policy DEVE chamar app.pagina_visivel(), nunca reescrever o predicado.
   Escrita: nenhum papel de usuário; só o worker via service_role.';
comment on column public.chunks.pagina_ini is
  'A citação depende disto (SPEC §3.4, §6.2): resultado de busca leva a "abrir na página X".
   Desde a correção de 2026-09-04 (ADR-0018) é também a âncora de visibilidade do chunk.';
```

**Trigger obrigatório — `chunks_valida_visibilidade_uniforme`** (ADR-0018):

```sql
-- [ADR-0019, achado V1] A verificação roda SEMPRE QUE EXISTIR OVERRIDE no intervalo do chunk —
-- não "quando tem_paginas_mistas = true". A flag é índice para pular a checagem no caso comum,
-- nunca a condição que decide se a segurança se aplica. Foi exatamente isso que o V1 derrubou.
-- Regra: um chunk só é aceito se TODAS as páginas do intervalo [pagina_ini, pagina_fim]
-- estiverem classificadas E com o MESMO nível.
-- Por quê: o chunk herda visibilidade pela pagina_ini — UMA borda do intervalo. Sem esta trava,
-- um chunk que começa na última página do regimento (público) e termina na primeira da ata
-- (autenticado) publicaria o texto da ata.
-- E isso não é caso raro: o chunking tem ~15% de overlap (SPEC §3.4) e atravessa fronteira de
-- página POR CONSTRUÇÃO — sem a trava, o vazamento seria o padrão, não a exceção.
-- Documento não-misto não paga este custo (a função retorna cedo).
create trigger chunks_valida_visibilidade_uniforme
  before insert or update of documento_id, pagina_ini, pagina_fim on public.chunks
  for each row execute function public.tg_chunks_valida_visibilidade_uniforme();
-- CONSEQUÊNCIA PARA O PIPELINE (F1): o chunker precisa respeitar fronteira de visibilidade ao
-- segmentar documento misto. Se não respeitar, o trigger rejeita e o documento não indexa.
-- É requisito do pipeline, não detalhe de banco.
--
-- A MENSAGEM DE EXCEÇÃO DESTE TRIGGER DEVE CITAR docs/adr/0021-invariante-de-dois-lados.md.
-- É o que a pessoa lê às duas da manhã quando a inserção falha — vale mais que qualquer índice
-- de documentação (ADR-0021 §4).
```

**O segundo caminho — `chunks_invalida_por_reclassificacao`** (ADR-0021, conserto do **V1-R**):

```sql
-- ACHADO V1-R: o trigger acima roda ao INSERIR o chunk. Nada revalidava quando
-- documento_paginas.visibilidade mudava DEPOIS — e essa é a ordem real do pipeline: o worker
-- chunkiza, a curadoria classifica em seguida. Resultado medido: texto sigiloso servido pela
-- busca com a chave `anon`.
--
-- Por que NÃO é só "adicionar um trigger que rejeita" (ADR-0021, nível 2 vs. nível 3): rejeitar a
-- reclassificação quebraria o fluxo de curadoria que motivou o modelo inteiro (ADR-0018).
-- Quando bloquear o segundo caminho impede um fluxo legítimo e frequente, a saída é INVALIDAR o
-- derivado, não barrar o fluxo.
create trigger chunks_invalida_por_reclassificacao
  after update of visibilidade on public.documento_paginas
  for each row execute function public.tg_invalida_chunks_da_pagina();
-- A função: DELETE dos chunks cujo [pagina_ini, pagina_fim] intersecta NEW.pagina,
--            + reenfileiramento do documento em job.fila (idempotente por sha256+versao_pipeline).
--
-- APAGAR, NÃO MARCAR COMO INVÁLIDO. Um flag `invalidado_em` obrigaria toda policy e toda consulta
-- de busca a lembrar de `and invalidado_em is null` — mais um predicado que alguém esquece, que é
-- exatamente o erro que o ADR-0021 trata. Linha apagada não vaza.
-- Custo honesto: a busca perde aqueles trechos até o reprocessamento terminar. Lacuna temporária
-- de busca é preferível a janela de vazamento — e a UI precisa dizer "reindexando", não mostrar
-- acervo incompleto sem explicação.
-- deliberacoes.chunk_id já é `on delete set null`, com âncora estável em (documento_id, pagina) +
-- trecho_literal (ADR-0016): a citação não quebra.
```

```
-- RLS — chunks
--   select : app.pagina_visivel(documento_id, pagina_ini)
--   insert/update/delete : nenhuma policy
-- Teste pgTAP obrigatório (auditor-rls), no mínimo:
--   1. anon NÃO lê chunk de documento 'autenticado'
--   2. morador NÃO lê chunk de documento 'conselho'
--   3. morador NÃO lê chunk de documento com status <> 'publicado'
--   4. morador de OUTRA unidade NÃO lê chunk de documento 'restrito'
--   5. conselho LÊ chunk de documento 'conselho'
--   6. [ADR-0018] anon LÊ chunk das páginas do regimento embutido numa ata 'autenticado'
--   7. [ADR-0018] anon NÃO lê chunk das páginas da ata no MESMO documento
--   8. [ADR-0018] chunk cruzando fronteira de visibilidade é REJEITADO na inserção
-- Se app.pagina_visivel() virar gargalo: desnormalizar visibilidade para chunks com
-- TRIGGER de sincronização a partir de documentos/documento_paginas. NUNCA duplicar o predicado.
```

---

## 7. Assembleias e deliberações

### 7.1 `assembleias` — F1

```sql
create table public.assembleias (
  id                  uuid primary key default gen_random_uuid(),
  tipo                public.tipo_assembleia not null,
  data                date not null,
  ata_documento_id    uuid references public.documentos(id) on delete restrict,
  edital_documento_id uuid references public.documentos(id) on delete restrict,
  quorum_presente     numeric(6,4) check (quorum_presente between 0 and 1),  -- fração, não dinheiro
  local               text,
  criado_em           timestamptz not null default now(),
  criado_por          uuid references public.pessoas(id)
);
create index assembleias_data_idx on public.assembleias (data desc);

comment on table public.assembleias is
  'RLS: leitura para autenticado; escrita só editor.
   Por quê: a existência e a data da assembleia são informação de convivência, não dado pessoal.
   O conteúdo sensível está na ATA, e a ata é um documento com sua própria visibilidade.';
```

### 7.2 `deliberacoes` — F1 · **[ADR-0016 item 1]**

```sql
create table public.deliberacoes (
  id             uuid primary key default gen_random_uuid(),
  assembleia_id  uuid not null references public.assembleias(id) on delete cascade,
  item           int not null check (item > 0),
  descricao      text not null,
  resultado      text not null check (resultado in ('aprovado','rejeitado','adiado','retirado')),
  votos_favor    int check (votos_favor >= 0),
  votos_contra   int check (votos_contra >= 0),
  abstencoes     int check (abstencoes >= 0),
  valor_autorizado_centavos bigint check (valor_autorizado_centavos >= 0),  -- ADR-0010

  -- ÂNCORA DE CITAÇÃO [ADR-0016 item 1]: estável, sobrevive a reprocessamento.
  documento_id   uuid references public.documentos(id) on delete restrict,
  pagina         int check (pagina > 0),
  trecho_literal text,   -- snapshot do texto citado, imune a rechunking

  -- Ponteiro FRACO para o chunk. Reprocessar o pipeline regenera chunks e ANULA esta coluna;
  -- a citação continua íntegra por documento_id + pagina + trecho_literal.
  chunk_id       uuid references public.chunks(id) on delete set null,

  criado_em      timestamptz not null default now(),
  criado_por     uuid references public.pessoas(id),
  constraint deliberacoes_uk unique (assembleia_id, item)
);
create index deliberacoes_documento_idx on public.deliberacoes (documento_id);

comment on table public.deliberacoes is
  'RLS: select se app.pagina_visivel(documento_id, pagina) OU documento_id is null e autenticado;
   escrita só editor.
   Por quê: a deliberação carrega trecho literal da ata — se a página citada é restrita, o trecho
   é restrito. Mesma lógica de espelhamento de chunks, por isso a mesma entrada por página
   (ADR-0018): numa ata mista, a deliberação está na parte autenticada, não na parte pública.';
comment on column public.deliberacoes.chunk_id is
  '[ADR-0016 item 1, aprovado em D8] SPEC §2 ancorava a citação em chunk_id. Chunk é derivado e
   volátil: SPEC §3 exige reprocessamento idempotente, que regenera a segmentação. Âncora estável
   = (documento_id, pagina) + trecho_literal. chunk_id vira otimização reconstruível, on delete
   set null.
   Por que âncora INLINE e não uma tabela `citacoes` com id próprio: lancamentos já ancora sua
   fonte inline (documento_id, pagina_origem). Uma tabela de citação criaria dois padrões
   diferentes de citação no mesmo schema e uma indireção para um relacionamento 1:1. Se um dia
   várias entidades precisarem citar o mesmo trecho, extrair a tabela é migração aditiva.';
```

> **[F1] Trigger `deliberacoes_ancora_so_ata`** (`20260906090100_taxonomia_f1_restricao_unidade_trigger.sql`):
> `documento_id`, quando preenchido, só pode referenciar um documento `tipo='ata_assembleia'` —
> nunca `resumo_assembleia`. Fonte: `docs/dominio/taxonomia-documental-decisoes.md` §3 — o
> resumo da administração pode ser indexado e citado em busca livre (chunks/documento_paginas
> continuam abertos a ele), mas não é prova de deliberação; só a ata ancora. A regra de citação
> propriamente dita (`Citacao.tipo`, selo "Resumo da administração · não é a ata oficial",
> precedência ata-sobre-resumo) é de `rag-citacao-juridica-ptbr`, fora do escopo de arquivo do
> `eng-supabase` — esta trigger só impede o dado de entrar torto no banco.

---

## 8. Financeiro

### 8.1 `contas` — F2 (semeada em F0) · árvore do plano de contas

```sql
create table public.contas (
  id               uuid primary key default gen_random_uuid(),
  codigo           text not null unique,   -- 'G.SS.CC' (condominio-plano-de-contas §1)
  nome             text not null,
  natureza         public.natureza_conta not null,
  nivel            int not null check (nivel between 1 and 3),
  conta_pai_id     uuid references public.contas(id) on delete restrict,
  aceita_lancamento boolean not null default false,   -- só folha (nível 3) recebe lançamento
  -- [D12 — REMOVIDAS] `contas.fundo` e `contas.exige_deliberacao` saem do modelo.
  -- Fundo é atributo do FATO (o lançamento), não natureza da conta: qualquer despesa pode ser
  -- paga com fundo de reserva — uma bomba emergencial tanto quanto uma obra planejada. Amarrar a
  -- regra a um conjunto fechado de contas produz FALSO NEGATIVO SILENCIOSO: o alerta não dispara
  -- para o gasto que ninguém previu, que é exatamente o que mais interessa fiscalizar.
  -- A conta sintética "2.12 Uso de fundos", criada no seed só para o alerta funcionar, sai junto:
  -- uso de fundo é a despesa finalística de sempre (2.3.x hidráulica, 2.4.x elevador, 2.10.x
  -- obra) com a origem do recurso marcada em `lancamentos.fundo`. Preserva "o quê" foi comprado
  -- e "de onde" saiu o dinheiro, sem duplicar valor no resultado nem divergir do balancete da
  -- administradora (docs/dominio/plano-de-contas-decisoes.md).
  -- ESPELHAMENTO 1:1 do plano da administradora. Divergir destrói comparabilidade
  -- (condominio-plano-de-contas §8). Nunca "corrigir" o nome dela.
  codigo_administradora text,
  nome_administradora   text,
  ativa            boolean not null default true,
  criado_em        timestamptz not null default now(),
  constraint contas_raiz_ck  check ((nivel = 1) = (conta_pai_id is null)),
  constraint contas_folha_ck check (not aceita_lancamento or nivel = 3)
  -- [D12] `contas_fundo_ck` removida junto com as colunas que ela validava.
);
create index contas_pai_idx    on public.contas (conta_pai_id);
create index contas_codigo_idx on public.contas (codigo text_pattern_ops);  -- prefixo '2.04.%'
-- Trigger recomendado: contas_valida_hierarquia — nivel = nivel(pai)+1, natureza igual à do pai,
-- e ausência de ciclo. CHECK não alcança a linha do pai.

comment on table public.contas is
  'RLS: leitura para autenticado; escrita só editor.
   Por quê: o plano de contas é o vocabulário do painel financeiro — o morador precisa ler para
   entender "para onde foi o dinheiro" (SPEC §6.4). Não contém PII. A escrita é sensível por
   outro motivo: renomear ou reclassificar conta reescreve o significado da série histórica.
   Mudança de plano é EVENTO REGISTRADO (auditado), não edição silenciosa.
   [D12] Esta tabela NÃO carrega regra de fiscalização. Nenhum alerta se avalia sobre atributo de
   conta — ver o padrão geral registrado em docs/04-DECISOES.md D12.';
```

### 8.2 `fornecedores` e `fornecedor_dados_bancarios` — F2 · **[ADR-0016 item 8]**

```sql
create table public.fornecedores (
  id            uuid primary key default gen_random_uuid(),
  cnpj          char(14) unique check (cnpj is null or cnpj ~ '^[0-9]{14}$'),  -- só dígitos
  -- Prestador pessoa física recebe EXATAMENTE o mesmo tratamento de CPF (ADR-0014 item 7).
  cpf_hash      bytea unique check (cpf_hash is null or octet_length(cpf_hash) = 32),
  cpf_enc       bytea,
  razao_social  text not null,
  nome_fantasia text,
  categoria     text,
  -- D3: o síndico terceirizado existe AQUI, como entidade fiscalizada. Não é papel, não é conta,
  -- não tem login, nenhum fluxo depende de ação dele dentro do produto.
  eh_sindico_terceirizado boolean not null default false,
  eh_administradora       boolean not null default false,
  ativo         boolean not null default true,
  criado_em     timestamptz not null default now(),
  criado_por    uuid references public.pessoas(id),
  constraint fornecedores_doc_ck check (cnpj is not null or cpf_hash is not null)
);
create index fornecedores_razao_trgm_idx on public.fornecedores using gin (razao_social gin_trgm_ops);
-- Mesma armadilha, mesma solução (ADR-0017): GRANT coluna a coluna, sem cpf_enc.
revoke all on public.fornecedores from public, anon, authenticated;
grant select (id, cnpj, cpf_hash, razao_social, nome_fantasia, categoria,
  eh_sindico_terceirizado, eh_administradora, ativo, criado_em, criado_por)
  on public.fornecedores to authenticated;
grant insert, update, delete on public.fornecedores to authenticated;

comment on table public.fornecedores is
  'RLS: leitura para autenticado (razão social e CNPJ de quem o condomínio paga é informação de
   prestação de contas); escrita só editor. cpf_enc fora do alcance por GRANT de coluna.
   Por quê D3: o síndico terceirizado é linha aqui, nunca usuário.';

-- Histórico de dados bancários. Existe SÓ para detectar o alerta crítico "troca de dados
-- bancários" (golpe do boleto, SPEC §5.3). Por isso guarda o MÍNIMO: nada em claro.
create table public.fornecedor_dados_bancarios (
  id             uuid primary key default gen_random_uuid(),
  fornecedor_id  uuid not null references public.fornecedores(id) on delete restrict,
  banco          text,
  agencia        text,
  conta_mascarada text,           -- '****1234' — suficiente para conferência humana
  chave_pix_hash bytea,           -- HMAC, mesmo esquema do CPF: compara sem armazenar
  vigente_desde  timestamptz not null default now(),
  vigente_ate    timestamptz,
  documento_id   uuid references public.documentos(id),
  registrado_por uuid references public.pessoas(id)
);
create index fdb_fornecedor_idx on public.fornecedor_dados_bancarios (fornecedor_id, vigente_ate);

comment on table public.fornecedor_dados_bancarios is
  'RLS: leitura e escrita só gestão (escrita só editor).
   Por quê: dado bancário de terceiro; e a própria mudança é o sinal de fraude que o alerta
   procura. Minimização deliberada: nada em claro — só máscara e hash.';
```

### 8.3 `contratos` — F2

```sql
create table public.contratos (
  id                    uuid primary key default gen_random_uuid(),
  fornecedor_id         uuid not null references public.fornecedores(id) on delete restrict,
  objeto                text not null,
  vigencia_inicio       date not null,
  vigencia_fim          date,
  valor_mensal_centavos bigint check (valor_mensal_centavos >= 0),  -- [ADR-0016 item 2] + ADR-0010
  indice_reajuste       text,                                       -- 'IPCA','IGPM','INPC',...
  documento_id          uuid references public.documentos(id) on delete restrict,
  -- Renovação acima da alçada exige ata (alerta "renovação não deliberada", SPEC §5.3):
  deliberacao_id        uuid references public.deliberacoes(id) on delete restrict,
  contrato_anterior_id  uuid references public.contratos(id),       -- cadeia de renovação
  encerrado_em          date,
  criado_em             timestamptz not null default now(),
  criado_por            uuid references public.pessoas(id),
  constraint contratos_vigencia_ck check (vigencia_fim is null or vigencia_fim >= vigencia_inicio)
);
create index contratos_fornecedor_idx on public.contratos (fornecedor_id);
create index contratos_vencimento_idx on public.contratos (vigencia_fim)
  where vigencia_fim is not null and encerrado_em is null;  -- alerta "contrato vencendo" (30 dias)

comment on table public.contratos is
  'RLS: leitura para autenticado; escrita só editor.
   Por quê: "quanto pagamos pela portaria" é pergunta legítima de qualquer morador (SPEC §6.2).
   Contrato com pessoa física que exponha dado individual deve entrar como documento de
   visibilidade conselho — a restrição fica no DOCUMENTO, não nesta linha.';
```

### 8.4 `periodos_fechados` — F2 · **[ADR-0016 item 8]**

```sql
-- Fechamento mensal trava o período; lançamento retroativo exige reabertura justificada e
-- auditada (SPEC §5.4).
create table public.periodos_fechados (
  competencia            date primary key
                         check (competencia = date_trunc('month', competencia::timestamp)::date),
  fechado_em             timestamptz not null default now(),
  fechado_por            uuid not null references public.pessoas(id),
  saldo_inicial_centavos bigint,
  saldo_final_centavos   bigint,
  reaberto_em            timestamptz,
  reaberto_por           uuid references public.pessoas(id),
  motivo_reabertura      text,
  constraint periodos_reabertura_ck check (
    reaberto_em is null or (reaberto_por is not null and length(btrim(motivo_reabertura)) >= 10))
);

comment on table public.periodos_fechados is
  'RLS: leitura para autenticado (o selo "mês fechado" é sinal de confiança na UI);
   escrita só editor.
   Por quê: é a trava que impede mexer no passado. saldo_final de um mês = saldo_inicial do
   seguinte é uma das três travas de consistência do SPEC §5.1.3.';
```

### 8.5 `lancamentos` — F2 · **imutável, correção por estorno (ADR-0011)**

```sql
create table public.lancamentos (
  id               uuid primary key default gen_random_uuid(),
  data_competencia date not null
                   check (data_competencia = date_trunc('month', data_competencia::timestamp)::date),
  data_caixa       date,
  conta_id         uuid not null references public.contas(id) on delete restrict,
  fornecedor_id    uuid references public.fornecedores(id) on delete restrict,
  historico        text not null check (length(btrim(historico)) >= 3),
  valor_centavos   bigint not null check (valor_centavos <> 0),   -- ADR-0010
  tipo             public.tipo_lancamento not null,
  -- [D12] Origem do recurso — atributo do FATO, ortogonal a conta_id ("o quê" foi comprado vs.
  -- "de onde" saiu o dinheiro). É sobre esta coluna que o alerta crítico "fundo sem ata" se
  -- avalia, nunca sobre atributo da conta. Ver docs/04-DECISOES.md D12.
  fundo            public.fundo not null default 'nenhum',

  -- SPEC §5.1.4: "todo lançamento nasce com documento_id + pagina_origem. Sem fonte, não existe."
  -- Por isso NOT NULL, e não "recomendado".
  documento_id     uuid not null references public.documentos(id) on delete restrict,
  pagina_origem    int not null check (pagina_origem > 0),

  origem           public.origem_lancamento not null default 'balancete_importado',
  -- [ADR-0016 item 6] Débito em fundo exige a ata que autorizou (SPEC §5.3, alerta crítico).
  deliberacao_id   uuid references public.deliberacoes(id) on delete restrict,

  -- ADR-0011: estorno é lançamento comum com self-FK e valor negativo.
  estorna_lancamento_id uuid unique references public.lancamentos(id) on delete restrict,
  motivo_estorno   text,

  criado_por       uuid not null references public.pessoas(id),
  criado_em        timestamptz not null default now(),

  -- Sinal amarrado ao papel da linha: normal > 0, estorno < 0. SUM() fica correto sem filtro.
  constraint lancamentos_sinal_ck check (
    (estorna_lancamento_id is     null and valor_centavos > 0) or
    (estorna_lancamento_id is not null and valor_centavos < 0)),
  constraint lancamentos_motivo_ck check (
    estorna_lancamento_id is null or length(btrim(motivo_estorno)) >= 10)
);

create index lancamentos_competencia_conta_idx on public.lancamentos (data_competencia, conta_id);
create index lancamentos_conta_competencia_idx on public.lancamentos (conta_id, data_competencia);
create index lancamentos_fornecedor_idx        on public.lancamentos (fornecedor_id, data_competencia);
create index lancamentos_documento_idx         on public.lancamentos (documento_id);
create index lancamentos_fundo_idx             on public.lancamentos (fundo, data_competencia)
  where fundo <> 'nenhum';
```

**Triggers obrigatórios** (o `eng-supabase` materializa; a semântica é esta):

```sql
-- 1) lancamentos_bloqueia_mutacao — BEFORE UPDATE OR DELETE.
--    Levanta exceção SEMPRE. Terceira camada do ADR-0011: REVOKE não alcança service_role
--    nem o dono da tabela; esta trava alcança. Manutenção estrutural legítima precisa
--    desabilitar o trigger explicitamente, dentro de migração revisada.

-- 2) lancamentos_valida_estorno — BEFORE INSERT, quando estorna_lancamento_id is not null:
--      a) o alvo existe e tem estorna_lancamento_id is null   (estorno de estorno é proibido)
--      b) new.valor_centavos = -alvo.valor_centavos           (exato, sem tolerância)
--      c) new.conta_id = alvo.conta_id e new.tipo = alvo.tipo e new.fundo = alvo.fundo
--         (estorno não reclassifica; reclassificar é estornar e lançar de novo)
--      d) new.documento_id herdado do alvo quando não houver documento novo
--    O "estornado no máximo uma vez" já vem do UNIQUE na self-FK.

-- 3) lancamentos_periodo_aberto — BEFORE INSERT:
--    rejeita competência com periodos_fechados.reaberto_em IS NULL (SPEC §5.4).
--    Vale também para o estorno.

-- 4) [D12 — REESCRITO] Alerta "fundo sem ata" avaliado sobre o FATO, não sobre a conta:
--       new.fundo <> 'nenhum' AND new.tipo = 'despesa' AND new.deliberacao_id IS NULL
--    Independente de conta_id. Índice já existe (lancamentos_fundo_idx).
--    NÃO bloqueia: gera alerta crítico (SPEC §5.3). Sinalizar, não bloquear silenciosamente
--    (condominio-plano-de-contas §4) — trava dura aqui produziria contorno criativo.
--    A versão anterior lia contas.exige_deliberacao e tinha falso negativo silencioso:
--    bastava lançar numa conta não marcada para o alerta nunca disparar.
--    Aporte AO fundo (entrada) é normal e não exige ata; o que exige é a SAÍDA — por isso
--    tipo = 'despesa' faz parte do predicado.
```

```sql
comment on table public.lancamentos is
  'RLS: leitura para autenticado (financeiro agregado é direito de qualquer condômino, SPEC §6.4-bis);
   INSERT só editor com AAL2; UPDATE e DELETE PARA NINGUÉM — sem policy, com REVOKE e com trigger.
   Por quê: quem publica é quem seria auditada (Risco §8.6, D4). Lançamento editável faz do
   balancete publicado uma afirmação, não uma prova — que é a dor nº2 do briefing.
   Correção é sempre estorno (ADR-0011), visível na UI, nunca escondida.';
```

```
-- RLS — lancamentos
--   select : app.eh_autenticado()
--   insert : app.eh_editor()
--   update : SEM POLICY  + revoke update from anon, authenticated + trigger que levanta exceção
--   delete : SEM POLICY  + revoke delete from anon, authenticated + trigger que levanta exceção
-- Teste pgTAP obrigatório: conselho NÃO insere lançamento; editor NÃO atualiza nem apaga;
-- service_role TAMBÉM não atualiza nem apaga (o trigger é o que prova isso).
```

### 8.6 `lancamento_anexos` — F2

```sql
create table public.lancamento_anexos (
  id             uuid primary key default gen_random_uuid(),
  lancamento_id  uuid not null references public.lancamentos(id) on delete restrict,
  storage_bucket text not null default 'anexos-financeiros',   -- bucket SEPARADO (SPEC §7)
  storage_path   text not null unique,
  sha256         bytea not null check (octet_length(sha256) = 32),
  tipo           text not null check (tipo in
                   ('nota_fiscal','recibo','boleto','comprovante_pagamento','cotacao',
                    'contrato','ordem_servico','outro')),
  descricao      text,
  enviado_por    uuid not null references public.pessoas(id),
  enviado_em     timestamptz not null default now()
);
create index lancamento_anexos_lancamento_idx on public.lancamento_anexos (lancamento_id);
-- Alerta "cotação ausente" (SPEC §5.3) conta tipo='cotacao' por lançamento acima do limiar.
create index lancamento_anexos_cotacao_idx on public.lancamento_anexos (lancamento_id)
  where tipo = 'cotacao';

comment on table public.lancamento_anexos is
  'RLS: leitura SÓ conselho e editor; escrita só editor.
   Por quê: nota fiscal e recibo carregam CNPJ, endereço, e às vezes nome de pessoa física.
   É o material mais sensível do financeiro. Bucket próprio, acesso só por signed URL de TTL
   curto gerada no servidor APÓS checagem de papel, nunca em página cacheada na CDN
   (SPEC §7, ADR-0004). Morador vê que o comprovante EXISTE (via view agregada), não o arquivo.';
```

### 8.7 `orcamento` — F2

```sql
create table public.orcamento (
  id                     uuid primary key default gen_random_uuid(),
  exercicio              int not null check (exercicio between 2000 and 2100),
  conta_id               uuid not null references public.contas(id) on delete restrict,
  mes                    int not null check (mes between 1 and 12),
  valor_previsto_centavos bigint not null check (valor_previsto_centavos >= 0),  -- [ADR-0016 item 2]
  documento_id           uuid references public.documentos(id) on delete restrict,
  criado_em              timestamptz not null default now(),
  criado_por             uuid references public.pessoas(id),
  constraint orcamento_uk unique (exercicio, conta_id, mes)
);

comment on table public.orcamento is
  'RLS: leitura para autenticado; escrita só editor.
   Por quê: orçado × realizado é o painel que o morador precisa ver (SPEC §6.4). Sem PII.
   É a base do alerta de estouro de orçamento (80% aviso / >100% crítico, SPEC §5.3).';
```

### 8.8 `cobrancas` — F2 · **a tabela de RLS mais delicada**

```sql
create table public.cobrancas (
  id                 uuid primary key default gen_random_uuid(),
  unidade_id         uuid not null references public.unidades(id) on delete restrict,
  competencia        date not null
                     check (competencia = date_trunc('month', competencia::timestamp)::date),
  valor_centavos     bigint not null check (valor_centavos > 0),        -- [ADR-0016 item 2]
  vencimento         date not null,
  status             public.status_cobranca not null default 'aberta',
  valor_pago_centavos bigint not null default 0 check (valor_pago_centavos >= 0),
  data_pagamento     date,
  documento_id       uuid references public.documentos(id) on delete restrict,
  criado_em          timestamptz not null default now(),
  atualizado_em      timestamptz not null default now(),
  constraint cobrancas_uk unique (unidade_id, competencia),
  constraint cobrancas_pagamento_ck check (
    status <> 'paga' or (data_pagamento is not null and valor_pago_centavos > 0))
);
create index cobrancas_status_vencimento_idx on public.cobrancas (status, vencimento);
create index cobrancas_unidade_idx           on public.cobrancas (unidade_id, competencia desc);

comment on table public.cobrancas is
  'RLS: morador vê SÓ as cobranças das PRÓPRIAS unidades; conselho e editor veem todas;
   escrita só editor.
   Por quê: inadimplência nominal JAMAIS é exposta a morador (SPEC §7, §5.5). Nome + unidade +
   valor em atraso de vizinho é dado pessoal negativo — e, na prática de condomínio, é o dado que
   gera conflito real. O agregado (taxa de inadimplência do mês) vai para todos por VIEW, não
   por acesso a esta tabela. Toda leitura nominal por gestão gera linha em audit.acesso
   (SPEC §5.5: "com log de acesso").';
```

```
-- RLS — cobrancas
--   select : unidade_id in (select app.unidades_da_pessoa())  OR  app.eh_gestao()
--   insert/update : app.eh_editor()
--   delete : ninguém (cancelar por status)
-- Teste pgTAP obrigatório: morador da unidade A NÃO lê cobrança da unidade B (nem uma linha,
-- nem uma contagem). É o teste que impede o vazamento mais provável do produto.
```

---

## 9. Fiscalização

### 9.1 `questionamentos` — F3

```sql
create table public.questionamentos (
  id             uuid primary key default gen_random_uuid(),
  lancamento_id  uuid not null references public.lancamentos(id) on delete restrict,
  autor_id       uuid not null references public.pessoas(id) on delete restrict,
  texto          text not null check (length(btrim(texto)) >= 10),
  status         public.status_questionamento not null default 'aberto',
  resposta       text,
  respondido_por uuid references public.pessoas(id),
  respondido_em  timestamptz,
  criado_em      timestamptz not null default now(),
  constraint questionamentos_resposta_ck check (
    status = 'aberto' or (resposta is not null and respondido_por is not null))
);
create index questionamentos_status_idx     on public.questionamentos (status);
create index questionamentos_lancamento_idx on public.questionamentos (lancamento_id);

comment on table public.questionamentos is
  'RLS: leitura e abertura SÓ conselho e editor; resposta só editor.
   Por quê SPEC §6.4-bis (STJ REsp 2.050.372): inspecionar documento é direito individual, mas
   EXIGIR CONTAS é direito coletivo — condômino sozinho não tem legitimidade. Questionamento
   formal é ato do órgão fiscalizador, não do morador. Dar INSERT ao morador aqui contradiria
   a restrição de copy do §6.4-bis no nível do dado, e não só na microcopy.';
```

### 9.2 `tipos_alerta` e `alertas` — F3

```sql
create table public.tipos_alerta (
  codigo             text primary key,   -- 'despesa_sem_comprovante','estouro_orcamento',...
  nome               text not null,
  severidade_padrao  public.severidade_alerta not null,
  descricao_regra    text not null,
  -- Pendência (b): quanto de série histórica a regra exige para produzir resultado com sentido.
  -- O motor NÃO avalia a regra enquanto o acervo não alcança este mínimo; a UI mostra
  -- "aguardando histórico" em vez de silenciar. Condomínio recém-entregue não tem 6 meses de
  -- média móvel, e regra sem base produz falso positivo em série.
  requer_historico_meses int not null default 0 check (requer_historico_meses >= 0),
  ativo              boolean not null default true
);
-- Seed: as 10 regras da tabela do SPEC §5.3. Os LIMIARES vivem em `configuracoes`,
-- não em código e não aqui (SPEC §5.3, última linha).
-- requer_historico_meses no seed: variacao_atipica = 6; fracionamento_suspeito = 3;
-- as demais = 0 (avaliáveis desde o primeiro balancete). Com o condomínio entregue em dez/2025
-- (D10), as duas já são avaliáveis — o motor compara contra a série REALMENTE disponível.
--
-- [D12] Toda regra deste seed se avalia sobre ATRIBUTO DO FATO, nunca sobre metadado de cadastro
-- que o operador controla. Fiscalização que depende de alguém ter marcado a caixinha certa antes
-- não é fiscalização — quem quer escapar não marca. Em particular:
--   fundo_sem_ata          -> lancamentos.fundo <> 'nenhum' AND tipo='despesa'
--                             AND deliberacao_id IS NULL   (NÃO contas.exige_deliberacao)
--   despesa_sem_comprovante-> ausência de lancamento_anexos (NÃO flag "exige comprovante")
--   cotacao_ausente        -> valor_centavos > limiar AND count(anexo tipo='cotacao') < 2
--                             (NÃO marcação de "conta que exige cotação")

create table public.alertas (
  id            uuid primary key default gen_random_uuid(),
  tipo          text not null references public.tipos_alerta(codigo) on delete restrict,
  severidade    public.severidade_alerta not null,
  lancamento_id uuid references public.lancamentos(id) on delete cascade,
  contrato_id   uuid references public.contratos(id)   on delete cascade,
  fornecedor_id uuid references public.fornecedores(id) on delete cascade,
  conta_id      uuid references public.contas(id)      on delete cascade,
  competencia   date,
  detalhe       jsonb not null default '{}'::jsonb,
  status        public.status_alerta not null default 'aberto',
  -- Idempotência: o motor é re-executável. Sem esta chave, cada execução duplica o alerta
  -- e o painel do conselho vira ruído — que é como um motor de alertas morre.
  chave_dedupe  text not null unique,
  criado_em     timestamptz not null default now(),
  resolvido_por uuid references public.pessoas(id),
  resolvido_em  timestamptz,
  resolucao     text,
  constraint alertas_alvo_ck check (
    num_nonnulls(lancamento_id, contrato_id, fornecedor_id, conta_id) >= 1)
);
create index alertas_status_severidade_idx on public.alertas (status, severidade);
create index alertas_competencia_idx       on public.alertas (competencia desc);

comment on table public.alertas is
  'RLS: leitura SÓ conselho e editor; escrita pelo motor (service_role); resolução só gestão.
   Por quê: alerta é acusação em potencial ("fracionamento suspeito", "troca de dados bancários").
   Exposto a morador antes de apuração, vira boato — e o sujeito do alerta é o síndico
   terceirizado, que sequer tem conta para se defender dentro do produto (D3).';
```

### 9.3 `pareceres` e `parecer_signatarios` — F3 · **[ADR-0016 item 8]**

```sql
create table public.pareceres (
  id                 uuid primary key default gen_random_uuid(),
  competencia_inicio date not null,
  competencia_fim    date not null,
  versao             int not null default 1 check (versao > 0),
  texto              text not null,
  conclusao          text check (conclusao in ('aprovado','aprovado_com_ressalva','rejeitado')),
  status             text not null default 'rascunho' check (status in ('rascunho','emitido')),
  documento_id       uuid references public.documentos(id) on delete restrict,
  emitido_em         timestamptz,
  criado_em          timestamptz not null default now(),
  constraint pareceres_periodo_ck check (competencia_fim >= competencia_inicio),
  constraint pareceres_uk unique (competencia_inicio, competencia_fim, versao)
);

create table public.parecer_signatarios (
  parecer_id  uuid not null references public.pareceres(id) on delete cascade,
  -- FK PRESERVADA: chave técnica dos agregados e da desambiguação de homônimo
  -- (juridico-lgpd §4: "pessoa_id: preservar sempre"). A FK liga; o snapshot atesta.
  pessoa_id   uuid not null references public.pessoas(id) on delete restrict,
  assinado_em timestamptz,

  -- [ADR-0020 / D14] SNAPSHOT DO ATO — única PII denormalizada autorizada no schema.
  -- Por quê: a identidade do signatário existia só em pessoas.nome, por FK. Anonimizado o
  -- ex-morador (rotina de fim + 5 anos), o signatário do parecer virava "ANONIMIZADO" — e parecer
  -- sem signatário identificável não tem valor probatório nenhum. Com editora única (D4), o
  -- parecer do conselho É a peça de contrapeso; perder o nome não degrada o registro, destrói a
  -- função dele.
  -- Base legal da retenção contra pedido de eliminação: LGPD art. 16, I (obrigação legal), porque
  -- a assinatura é a validade do ato — CC art. 1.356 (juridico-lgpd §4, lista do que nunca se
  -- anonimiza).
  -- LIMITE ESTREITO, por necessidade (LGPD art. 6º, III): congela-se o MÍNIMO que torna o ato
  -- atribuível. Nome e qualificação, sim. CPF, e-mail, telefone, unidade: PROIBIDO acrescentar
  -- aqui — nada disso é elemento da assinatura, e usar exceção estreita como guarda-chuva é o
  -- abuso clássico do art. 16.
  nome_signatario text,   -- congelado quando assinado_em deixa de ser nulo
  qualificacao    text,   -- 'Conselho fiscal, mandato 2026/2028' — em que qualidade assinou

  primary key (parecer_id, pessoa_id)
);

-- Triggers obrigatórios (ADR-0020):
--  1) parecer_signatarios_congela_snapshot — BEFORE INSERT OR UPDATE:
--     quando assinado_em passa de NULL a preenchido, copia pessoas.nome e a qualificação do papel
--     vigente. ANTES DA ASSINATURA NÃO HÁ ATO, logo não há o que congelar — rascunho com
--     signatário previsto não gera retenção de PII.
--  2) parecer_signatarios_snapshot_imutavel — BEFORE UPDATE:
--     rejeita alteração de nome_signatario/qualificacao já preenchidos. Snapshot reescrevível não
--     é snapshot. Nome corrigido em pessoas (casamento, retificação) NÃO propaga para parecer já
--     assinado — o ato foi assinado com aquele nome; retificação é anotação nova, nunca reescrita.
--
-- A rotina de anonimização NÃO precisa conhecer exceção: ela atua em `pessoas`, e estas colunas
-- não vivem lá. É a diferença entre depender de um WHERE ... NOT IN (signatários) que alguém
-- precisa escrever certo e não haver nada a excluir.

comment on column public.parecer_signatarios.nome_signatario is
  'ADR-0020: snapshot do nome no momento da assinatura. PII denormalizada AUTORIZADA em caráter
   excepcional e de escopo fechado — ver o critério de três testes em docs/adr/0020. Não é
   precedente: denormalizar PII exige que o dado seja ELEMENTO DO ATO (T1), tenha base legal que
   impeça a eliminação (T2) e deva ficar congelado no tempo (T3). Os três, não a maioria.';

comment on table public.parecer_signatarios is
  'RLS: mesma de pareceres. Escrita: conselho (o próprio signatário registra a assinatura).
   Por quê o snapshot (ADR-0020, D14): sem ele, anonimizar o ex-conselheiro apagava a identidade
   de quem assinou o parecer. Um conselheiro que vende o apartamento é, ao mesmo tempo, titular
   com direito à eliminação (LGPD art. 18) e signatário de ato cuja assinatura é a validade dele
   (CC art. 1.356). O snapshot separa as duas coisas: o cadastro é eliminado, o ato permanece.';

comment on table public.pareceres is
  'RLS: rascunho SÓ conselho e editor; parecer emitido, leitura para autenticado. Escrita: conselho.
   Por quê: é a única escrita do papel conselho — e ela não toca lançamento (SPEC §2.1).
   O rigor de assinatura/versionamento depende do Briefing §7 item 3 (se o parecer tem valor
   formal perante a assembleia), ainda PENDENTE. O desenho comporta as duas respostas.';
```

---

## 10. Busca e configuração

```sql
-- Expansão de sinônimo acontece NA APLICAÇÃO (SPEC §4): Supabase gerenciado não dá acesso a
-- $SHAREDIR para dicionário synonym/thesaurus.
create table public.sinonimos (
  id         uuid primary key default gen_random_uuid(),
  termo      text not null,
  termo_normalizado text generated always as (lower(public.unaccent_imutavel(termo))) stored,
  expansoes  text[] not null check (cardinality(expansoes) > 0),
  ativo      boolean not null default true,
  criado_em  timestamptz not null default now()
);
create unique index sinonimos_normalizado_uk on public.sinonimos (termo_normalizado);
-- Seed (SPEC §4): 'taxa condominial' -> {cota, rateio}; 'fundo de reserva' -> {FR, reserva técnica};
-- 'prestação de contas' -> {balancete}; 'AGE' -> {assembleia extraordinária}.

comment on table public.sinonimos is
  'RLS: leitura para todos (inclusive anon — a busca pública em convenção/regimento precisa);
   escrita só editor. Sem PII.';

-- Limiares e parâmetros vivem em tabela, nunca em código (SPEC §5.3).
create table public.configuracoes (
  chave         text primary key,
  valor         jsonb not null,
  descricao     text,
  publica       boolean not null default false,  -- se a UI do morador pode ler
  atualizado_em timestamptz not null default now(),
  atualizado_por uuid references public.pessoas(id)
);
-- Seed: limiar_cotacao_centavos=500000 (R$5.000, SPEC §5.3); orcamento_aviso_pct=80;
-- orcamento_critico_pct=100; variacao_atipica_pct=30; ocr_min_chars_pagina=100;
-- ocr_max_gibberish_ratio; contrato_aviso_dias=30; rrf_k=60; busca_top_k=50.
-- Pendência (b): condominio_data_instalacao (date) e competencia_mais_antiga (date, derivada de
-- lancamentos). O motor de alertas compara requer_historico_meses contra a série realmente
-- disponível — não contra a data de hoje. Qualquer resposta da dona do projeto entra aqui como
-- valor, sem migração.

comment on table public.configuracoes is
  'RLS: leitura de linha com publica=true para autenticado; demais SÓ gestão; escrita só editor.
   Por quê: limiar de alerta é informação de fiscalização — saber que a cotação só é exigida
   acima de R$5.000 é convite a fracionar em R$4.999 (que é justamente o alerta
   "fracionamento suspeito"). Toda alteração é auditada.';
```

---

## 11. Fila de processamento — schema `job` (ADR-0007)

```sql
create table job.fila (
  id                 bigint generated always as identity primary key,
  tipo               text not null,           -- 'ingestao_documento','ocr_pagina','embedding_lote',...
  payload            jsonb not null,
  status             public.status_job not null default 'pendente',
  prioridade         int not null default 100,
  tentativas         int not null default 0,
  max_tentativas     int not null default 5,
  disponivel_em      timestamptz not null default now(),   -- backoff exponencial
  iniciado_em        timestamptz,                          -- lease: recupera worker morto
  concluido_em       timestamptz,
  erro               text,
  -- SPEC §3: "job re-executável por sha256 + versão do pipeline"
  -- [F1/ADR-0025 §2, ADR-0026 §1] `unique` deixou de ser TOTAL em 2026-09-06 — virava no-op
  -- permanente em `on conflict do nothing` depois que o primeiro job de uma chave concluía,
  -- fechando a porta para reprocessamento (bug E2). Ver índice parcial abaixo.
  chave_idempotencia text,
  criado_em          timestamptz not null default now()
);
create index fila_pronto_idx on job.fila (prioridade, disponivel_em)
  where status = 'pendente';
create index fila_travado_idx on job.fila (iniciado_em)
  where status = 'processando';   -- varredura de lease expirado

-- [F1/ADR-0025 §2] Unicidade PARCIAL: impede job pendente/processando duplicado para a mesma
-- chave (execução simultânea, enfileiramento duplicado por caminhos concorrentes). NÃO impede
-- reenfileirar a mesma chave depois que o job anterior CONCLUIU — linhas concluídas ficam como
-- histórico. job.enfileirar() (abaixo) é o único ponto que insere contra este índice.
create unique index fila_chave_idempotencia_ativa_uk on job.fila (chave_idempotencia)
  where status in ('pendente', 'processando');

-- [F1/ADR-0025 §Consequências] Índice de job por documento: sustenta "quais jobs pendentes/
-- processando existem para este documento?" (botão "tentar de novo", sentinela do ADR-0026,
-- tela de acervo). job.enfileirar() garante que payload sempre carrega 'documento_id'.
create index fila_documento_idx on job.fila ((payload ->> 'documento_id'))
  where status in ('pendente', 'processando');

-- Consumo: SELECT ... FOR UPDATE SKIP LOCKED. Sem RLS e sem GRANT para anon/authenticated:
-- o schema job não é exposto pelo PostgREST e o worker conecta com credencial própria.
comment on table job.fila is
  'RLS: irrelevante — schema fora do PostgREST, sem GRANT a papel de usuário.
   Por quê: o payload carrega caminho de storage e identificadores; não é dado de usuário e
   nenhuma tela precisa dele. Vigilância obrigatória: job "processando" com iniciado_em antigo
   volta a pendente, senão um crash de worker engole o documento em silêncio (ADR-0007).';
```

### 11.1 `job.enfileirar` — [F1/ADR-0025 §2, ADR-0026 §1] único caminho de enfileiramento

```sql
create or replace function job.enfileirar(
  p_tipo         text,
  p_documento_id uuid,
  p_chave        text,
  p_payload      jsonb,
  p_prioridade   int default 100
)
returns bigint
language plpgsql security definer set search_path = '' as $$
  -- valida p_tipo/p_documento_id/p_chave (raise se nulo/vazio);
  -- v_payload := coalesce(p_payload,'{}') || jsonb_build_object('documento_id', p_documento_id::text);
  -- insert into job.fila (tipo, payload, chave_idempotencia, prioridade)
  --   values (p_tipo, v_payload, p_chave, coalesce(p_prioridade,100))
  --   on conflict (chave_idempotencia) where status in ('pendente','processando') do nothing
  --   returning id into v_id;
  -- return v_id;  -- NULL quando já havia job ativo com esta chave
$$;
revoke all on function job.enfileirar(text, uuid, text, jsonb, int) from public;
grant usage on schema job to authenticated;
grant execute on function job.enfileirar(text, uuid, text, jsonb, int) to authenticated, service_role;
```

SECURITY DEFINER porque `job.fila` não tem GRANT direto para `authenticated` (schema fora do
PostgREST). Todo enfileiramento — Server Action de upload, o worker ao concluir um estágio, o
trigger invalidador de chunks (ADR-0026 caminho 3, **corte C4, implementado 2026-09-06**), ação
humana de curadoria, comando de reprocessamento, botão "tentar de novo" — passa por esta função.
`insert` direto em `job.fila` não existe em lugar nenhum: `authenticated` e `anon` não têm GRANT
na tabela, só EXECUTE na função (testado em `supabase/tests/07_job_enfileirar_idempotencia_parcial.sql`).

### 11.2 Reenfileiramento automático e a sentinela — [F1/ADR-0026, corte C4]

Três triggers, em `20260906140000_reprocessamento_enfileirado_e_sentinela.sql`, fazem
"apagou implica pediu para refazer" ser uma propriedade do banco, não promessa do worker:

- `chunks_marca_indexado` (`AFTER INSERT` em `chunks`) — seta `documentos.indexado_em = now()`
  quando um chunk da versão CORRENTE do pipeline é inserido.
- `chunks_invalida_documento` (`AFTER DELETE` em `chunks`) — zera `indexado_em` e chama
  `job.enfileirar('chunking', ...)` quando um chunk da versão corrente é apagado, por QUALQUER
  caminho (invalidador de página, ou "à mão" por `service_role`). `on conflict do nothing` (índice
  parcial, §11) absorve o caso comum: o próprio worker apagando+reinserindo na mesma transação.
- `documentos_versao_pipeline_invalida_indexacao` (`BEFORE UPDATE OF versao_pipeline` em
  `documentos`) — zera `indexado_em` e enfileira para a versão NOVA; bumpar a versão não apaga
  nenhum chunk (a cauda velha fica), então o mecanismo acima nunca dispararia sozinho.
- `documento_paginas_invalida_chunks_afetados` (baseline 08) passou a disparar também em `DELETE`,
  não só `INSERT`/`UPDATE OF visibilidade` — apagar uma página com override e derrubá-la para o
  piso do documento podia quebrar a uniformidade de um chunk existente sem deixar rastro.

```sql
create view app.documentos_fora_da_busca as
select d.id as documento_id, d.titulo, d.tipo, d.status, d.visibilidade, d.versao_pipeline,
       d.indexado_em, d.atualizado_em, j.tem_job_ativo, j.job_mais_antigo_desde
from public.documentos d
left join lateral (
  select count(*) > 0 as tem_job_ativo, min(f.criado_em) as job_mais_antigo_desde
    from job.fila f
   where f.tipo = 'chunking' and f.status in ('pendente','processando')
     and f.payload ->> 'documento_id' = d.id::text
) j on true
where app.eh_gestao() and d.status = 'publicado' and d.indexado_em is null;
```

`security_invoker = false` (exceção documentada, mesma classe de `vw_inadimplencia_agregada`
abaixo, §14): precisa ler `job.fila`, que não tem GRANT para papel de usuário nenhum.
`app.eh_gestao()` no `WHERE` é defesa em profundidade (achado V6) — `GRANT select` vai só para
`authenticated`, nunca `anon`. **Mostra o documento mesmo com job ativo** de propósito — é o
sinal "fora da busca AGORA" (INV-13); `tem_job_ativo`/`job_mais_antigo_desde` deixam quem CONSOME
a view (UI, runbook) distinguir "sendo reindexado" de "ninguém encarregado" sem duplicar a query.
Prova completa, matriz e testes vermelhos: `docs/invariantes/INV-13-...md`.

---

## 12. Trilha de auditoria — schema `audit` (ADR-0013)

```sql
-- ============================================================================
-- audit.log — mutação de dado. Append-only, encadeada por hash, PERMANENTE.
-- ============================================================================
create table audit.log (
  seq           bigint generated always as identity primary key,
  ts            timestamptz not null default clock_timestamp(),
  actor_uid     uuid,          -- auth.uid()
  actor_pessoa_id uuid,
  actor_papel   text,
  acao          text not null check (acao in ('INSERT','UPDATE','DELETE','TRUNCATE')),
  schema_nome   text not null,
  tabela        text not null,
  registro_id   text,
  antes         jsonb,
  depois        jsonb,
  ip            inet,
  user_agent    text,
  hash_anterior bytea,
  hash_registro bytea not null unique
);
create index log_tabela_registro_idx on audit.log (tabela, registro_id, seq desc);
create index log_ts_idx              on audit.log (ts desc);

-- Imutabilidade em duas camadas. REVOKE não alcança o dono da tabela nem superusuário;
-- o trigger alcança.
revoke update, delete, truncate on audit.log from public;
-- + trigger BEFORE UPDATE OR DELETE OR TRUNCATE que levanta exceção sempre.

-- ----------------------------------------------------------------------------
-- SERIALIZAÇÃO CANÔNICA — parte do contrato. Mudar isto quebra a cadeia.
--   canonico = convert_to( jsonb_build_object(
--       'seq', seq, 'ts', ts, 'actor_uid', actor_uid, 'acao', acao,
--       'schema', schema_nome, 'tabela', tabela, 'registro_id', registro_id,
--       'antes', antes, 'depois', depois )::text, 'UTF8')
--   hash_registro = extensions.digest(coalesce(hash_anterior,'\x00'::bytea) || canonico,'sha256')
-- jsonb ordena e deduplica chaves de forma determinística -> hash reproduzível por qualquer
-- verificador que leia a linha.
-- ----------------------------------------------------------------------------

-- audit.fn_registrar() — AFTER INSERT/UPDATE/DELETE FOR EACH ROW, SECURITY DEFINER.
-- Obrigações da função, em ordem:
--   1. pg_advisory_xact_lock(<chave fixa>) ANTES de ler o último hash_registro.
--      Sem isso, duas transações concorrentes leem o mesmo hash_anterior e a cadeia BIFURCA —
--      falha que só aparece sob carga e destrói a garantia em silêncio.
--   2. REDIGIR colunas sensíveis em antes/depois: cpf_enc -> '[redigido]'.
--      Senão a trilha vira segunda cópia irremovível de dado pessoal (ADR-0013).
--   3. Gravar actor_papel = app.papel_atual().

-- Tabelas auditadas: pessoas, papeis, vinculos, documentos, documento_unidades, lancamentos,
--   lancamento_anexos, orcamento, cobrancas, fornecedores, fornecedor_dados_bancarios,
--   contratos, deliberacoes, assembleias, configuracoes, periodos_fechados, questionamentos,
--   pareceres, contas.
-- NÃO auditadas: chunks, documento_paginas, job.fila — saída determinística de máquina, alto
--   volume, sem intenção humana; reproduzíveis a partir do PDF original.

-- ============================================================================
-- audit.ancoras — âncora semanal do hash-topo, enviada por e-mail ao conselho (SPEC §7).
-- É o que impede reescrever o passado E recomputar a cadeia inteira para casar.
-- ============================================================================
create table audit.ancoras (
  id         uuid primary key default gen_random_uuid(),
  ate_seq    bigint not null,
  hash_topo  bytea not null,
  gerada_em  timestamptz not null default now(),
  enviada_em timestamptz,
  destinatarios text[]
);

-- ============================================================================
-- audit.acesso — LEITURA de dado sensível. SEM encadeamento, EXPURGÁVEL em 6 meses.
-- [ADR-0016 item 9] Separada de audit.log de propósito: SPEC §7 exige retenção de 6 meses para
-- log de acesso, e expurgo é INCOMPATÍVEL com cadeia de hash. Misturar as duas obrigaria a
-- escolher entre violar a retenção e quebrar a cadeia.
-- ============================================================================
create table audit.acesso (
  id         bigint generated always as identity primary key,
  ts         timestamptz not null default now(),
  actor_pessoa_id uuid,
  recurso    text not null,   -- 'cpf_em_claro','inadimplencia_nominal','anexo_financeiro','export'
  recurso_id text,
  motivo     text,
  ip         inet
);
create index acesso_ts_idx on audit.acesso (ts desc);
create index acesso_recurso_idx on audit.acesso (recurso, ts desc);

-- audit.verificar_cadeia(desde bigint default 1, ate bigint default null)
--   recalcula o encadeamento e devolve a PRIMEIRA linha inconsistente (ou nada).
--   Roda semanalmente, antes de gerar a âncora, e sob demanda.
--
-- ACHADO V5-R (ADR-0021) — `seq` DÁ ORDEM, NÃO ENDEREÇO.
-- A função semeava o hash anterior com `where seq = desde - 1`, tratando um ordinal como
-- endereço. Identidade e sequência NUNCA prometem contiguidade: toda transação abortada queima um
-- nextval. Com um buraco, a linha "anterior" não existe, o seed fica nulo e o verificador acusa
-- quebra falsa em cadeia intacta — e alarme falso permanente é o mesmo que nenhuma detecção,
-- porque adulteração real fica indistinguível do ruído.
--   errado: select hash_registro from audit.log where seq = desde - 1;
--   certo : select hash_registro from audit.log where seq < desde order by seq desc limit 1;
-- Regra reutilizável: onde for preciso "a linha anterior", peça por ORDEM, nunca por aritmética.
```

---

## 13. Storage (ADR-0004)

```sql
-- Buckets criados na baseline via storage.buckets:
--   ('documentos',         public = false)
--   ('anexos-financeiros', public = false)   -- bucket SEPARADO por exigência do SPEC §7
--   ('publicos',           public = true)    -- SOMENTE convenção e regimento
--
-- RLS em storage.objects — o eng-supabase materializa; a intenção é:
--   bucket 'documentos':         select se exists(documentos d where d.storage_path = name
--                                                 and app.documento_visivel(d.id))
--                                <- ENTRADA DE DOCUMENTO, de propósito (ADR-0018): o PDF cru não
--                                é fatiado por página. Anônimo não baixa a ata de 36 páginas
--                                porque 12 delas são públicas. A granularidade por página vale
--                                para texto extraído, busca e citação — não para o arquivo.
--                                [ADR-0019] Este gate está CORRETO porque a invariante do piso
--                                garante que documentos.visibilidade é o nível do conteúdo mais
--                                sensível do arquivo. Sem a invariante, esta policy liberava PDF
--                                com página restrita dentro (V3). Nada mudou na policy; mudou a
--                                garantia por trás dela.
--   bucket 'anexos-financeiros': select se app.eh_gestao()
--   bucket 'publicos':           select para todos
--   insert/update/delete em todos: nenhum papel de usuário — upload é por signed upload URL
--                                  emitida no servidor.
--
-- Por quê a RLS existe mesmo com signed URL: a URL assinada contorna RLS por construção, e a
-- checagem de papel acontece ANTES de assinar. A RLS em storage.objects é a segunda camada,
-- para acesso direto com o JWT do usuário.
```

---

## 14. Views (SPEC §2: "orçado×realizado e inadimplência são views, não materializadas")

`security_invoker = true` em todas — a view herda a RLS de quem consulta; view não é fronteira
de autorização (ADR-0012, alternativa descartada).

| View | Fase | Conteúdo | Observação |
|---|---|---|---|
| `vw_orcado_realizado` | F2 | `exercicio, mes, conta_id, previsto_centavos, realizado_centavos, variacao_centavos, variacao_pct` | `SUM(valor_centavos)` já correto: estorno é negativo (ADR-0011) |
| `vw_realizado_por_conta` | F2 | série por conta e competência | base de "para onde foi o dinheiro" (SPEC §6.4) |
| `vw_inadimplencia_agregada` | F2 | `competencia, total_centavos, em_atraso_centavos, pct, qtd_unidades_em_atraso` | **sem `unidade_id`** — é a view que o morador lê |
| `vw_inadimplencia_nominal` | F2 | unidade + pessoa + valor | herda RLS de `cobrancas`: morador só enxerga a própria linha; leitura por gestão registra em `audit.acesso` |
| `vw_pessoas_mascaradas` | F0 | `id, nome, email, cpf_mascarado` | `cpf_mascarado = '***.***.' \|\| cpf_ultimos_digitos \|\| '-**'`; não toca `cpf_enc` |
| `vw_documentos_publicados` | F1 | acervo com status `publicado` | conveniência de listagem |
| `vw_lancamentos_com_comprovante` | F2/F3 | lançamento + contagem de anexos por tipo | morador vê que o comprovante **existe**, sem acessar o arquivo |
| `app.documentos_fora_da_busca` | F1 | documento publicado sem índice de busca válido + sinal de job ativo | **fora da tabela acima de propósito**: vive em `app` (fora do `db.exposed_schemas` do PostgREST), gestão-only, `security_invoker=false` — ver §11.2 |

> `SUM(bigint)` devolve `numeric` no Postgres (promoção para evitar overflow). O código de
> aplicação precisa esperar `numeric`, não `bigint` (ADR-0010).

---

## 15. Matriz consolidada de RLS

`—` = sem policy (negado). Escrita de `editor` sempre exige AAL2 (ADR-0003).

> `documentos` na tabela abaixo é rotulado `documento_visivel` pelo ALCANCE de autorização
> (mesmo quem vê o quê de sempre); desde 2026-09-06 a policy avalia isso com predicado local
> em vez de chamar a função — ver a nota de correção da §4/§6.2 (RETURNING/MVCC, ADR-0023).

| Tabela | anon | morador | conselho | editor | escrita |
|---|---|---|---|---|---|
| `unidades` | — | ler | ler | ler | editor |
| `pessoas` | — | própria linha | todas (sem `cpf_enc`) | todas | editor |
| `vinculos` | — | própria unidade | todos | todos | editor |
| `papeis` | — | próprios | todos | todos | editor |
| `tipos_documento` | ler | ler | ler | ler | editor |
| `documentos` | `documento_visivel` | `documento_visivel` | tudo | tudo | editor |
| `documento_unidades` | — | própria unidade | todos | todos | editor |
| `documento_paginas` | **`pagina_visivel`** | **`pagina_visivel`** | **`pagina_visivel`** | **`pagina_visivel`** | — (worker) |
| `chunks` | **`pagina_visivel`** (via `pagina_ini`) | **idem** | **idem** | **idem** | — (worker) |
| `assembleias` | — | ler | ler | ler | editor |
| `deliberacoes` | `pagina_visivel` | `pagina_visivel` | tudo | tudo | editor |
| `contas` | — | ler | ler | ler | editor |
| `fornecedores` | — | ler (sem `cpf_enc`) | ler | ler | editor |
| `fornecedor_dados_bancarios` | — | — | ler | ler | editor |
| `contratos` | — | ler | ler | ler | editor |
| `periodos_fechados` | — | ler | ler | ler | editor |
| `lancamentos` | — | ler | ler | ler | **insert editor; update/delete ninguém** |
| `lancamento_anexos` | — | — | ler | ler | editor |
| `orcamento` | — | ler | ler | ler | editor |
| `cobrancas` | — | **própria unidade** | todas | todas | editor |
| `questionamentos` | — | — | ler + abrir | ler + responder | conselho abre, editor responde |
| `tipos_alerta` | — | — | ler | ler | editor |
| `alertas` | — | — | ler + resolver | ler + resolver | motor (service_role) |
| `pareceres` | — | só `emitido` | ler todos | ler todos | conselho |
| `sinonimos` | ler | ler | ler | ler | editor |
| `configuracoes` | — | só `publica` | todas | todas | editor |
| `job.fila` | fora do PostgREST | | | | worker |
| `audit.*` | fora do PostgREST | | | | trigger `SECURITY DEFINER` |

---

## 16. Checklist de materialização (para `eng-supabase`)

Ordem de criação na baseline — respeitar, porque há dependência de FK e de tipo:

1. extensões → schemas → `revoke` de default privileges
2. `public.pt_br` (config de texto) e `public.unaccent_imutavel()` — **antes** de `chunks`
3. enums
4. `unidades`, `pessoas`, `vinculos`, `papeis`
5. funções `app.*` (dependem de `pessoas`, `papeis`, `vinculos`)
6. `tipos_documento`, `documentos`, `documento_unidades`, `documento_paginas`, `chunks`
7. `app.nivel_visivel()`, `app.nivel_efetivo()`, `app.documento_visivel()`, `app.pagina_visivel()`
   e o trigger `chunks_valida_visibilidade_uniforme` (dependem de `documentos`,
   `documento_paginas` e `documento_unidades`)
8. `assembleias`, `deliberacoes`
9. `contas`, `fornecedores`, `fornecedor_dados_bancarios`, `contratos`, `periodos_fechados`
10. `lancamentos` (+ 4 triggers), `lancamento_anexos`, `orcamento`, `cobrancas`
11. `questionamentos`, `tipos_alerta`, `alertas`, `pareceres`, `parecer_signatarios`
12. `sinonimos`, `configuracoes`
13. `job.fila`
14. `audit.log`, `audit.ancoras`, `audit.acesso`, `audit.fn_registrar()`, triggers de auditoria
15. buckets de Storage
16. **`enable row level security` + `force row level security` + `revoke`/`grant` de cada tabela,
    na mesma migração em que a tabela é criada** (ADR-0008 item 5) — nunca depois
17. views (`security_invoker = true`)
18. `comment on table` de cada tabela, reproduzindo o bloco de RLS deste documento

Verificações que precisam passar antes de considerar a baseline pronta:

- [ ] `supabase db reset` aplica limpo, do zero, sem erro
- [ ] nenhuma tabela em `public` com `relrowsecurity = false`
- [ ] nenhuma tabela em `public` sem ao menos uma policy **ou** sem `revoke` explícito
- [ ] `app`, `audit` e `job` ausentes de `db.exposed_schemas` no `config.toml`
- [ ] `update`/`delete` em `lancamentos` falha **inclusive com `service_role`**
- [ ] `update`/`delete` em `audit.log` falha **inclusive com `service_role`**
- [ ] `select cpf_enc` como `authenticated` falha por privilégio de coluna — e o `GRANT` de
      `pessoas`/`fornecedores` é lista explícita, **sem** nenhum `grant select on <tabela>` nem
      `revoke select (coluna)` (ADR-0017; `revoke` de coluna não faz efeito e dá falsa segurança)
- [ ] `anon` lê a página com override `publico` dentro de documento `autenticado`, e **não** lê a
      página seguinte do mesmo documento (ADR-0018)
- [ ] em documento `tem_paginas_mistas`, página com `visibilidade` NULL não é lida por não-gestão
- [ ] `insert` de chunk cruzando fronteira de visibilidade é rejeitado pelo trigger — **e é
      rejeitado também com `tem_paginas_mistas = false`**, se houver override no intervalo (V1)
- [ ] override de página mais restritivo que o documento é **rejeitado** (V3, invariante do piso)
- [ ] afrouxar `documentos.visibilidade` acima de uma página já classificada é **rejeitado**
- [ ] `tem_paginas_mistas` liga sozinha ao surgir o primeiro override, e não pode ser desligada
      enquanto houver override
- [ ] `app.ordem_visibilidade` bate com a audiência real: para cada par de níveis, quem enxerga o
      mais restritivo é subconjunto de quem enxerga o mais permissivo — em especial
      `conselho ⊂ restrito` (o nome engana)
- [ ] não existe documento baixável por um papel que não possa ler alguma de suas páginas
- [ ] anonimizar `pessoas` **não** apaga `parecer_signatarios.nome_signatario` (ADR-0020)
- [ ] `UPDATE` de `nome_signatario`/`qualificacao` já preenchidos é rejeitado
- [ ] linha de signatário sem `assinado_em` tem snapshot **nulo** (não há ato, não há retenção)
- [ ] **[V3-R]** afrouxar `documentos.visibilidade` acima de uma página já classificada é rejeitado
- [ ] **[V1-R]** reclassificar `documento_paginas.visibilidade` **apaga** os chunks que intersectam
      a página e reenfileira o documento — e o chunk antigo não é legível no intervalo
- [ ] **[V5-R]** `verificar_cadeia` não acusa quebra numa cadeia com buraco de `seq`
      (teste: abortar uma transação de propósito, queimar um `nextval`, e verificar)
- [ ] **[V10]** desativar a última pessoa com `editor` vigente falha; com duas, passa
- [ ] toda invariante relacional do schema tem a **matriz de caminhos** no comentário da sua
      migração, sem célula vazia (ADR-0021)
- [ ] nenhuma policy de `documento_paginas`, `chunks` ou `deliberacoes` chama
      `app.documento_visivel` (entrada errada — ver tabela normativa da §4)
- [ ] `insert` de documento tipo `ata_assembleia` com `visibilidade = 'publico'` é rejeitado
- [ ] coluna gerada `chunks.tsv` compila (prova que a config `pt_br` está qualificada)
- [ ] `insert` de estorno com valor diferente de `-original` é rejeitado
- [ ] `insert` concorrente em tabela auditada não bifurca a cadeia (teste com 2 sessões)
