-- Breeze — ADR-0030: vigência de papel e de vínculo é intervalo MEIA-ABERTO EM INSTANTE,
-- não período em dias. Fecha a dívida R4 (docs/ops/divida-tecnica.md).
--
-- Migração ÚNICA, de propósito (ADR-0030, Especificação, passo 0): estado meio-aplicado NÃO é
-- inofensivo. Postgres promove `date` a `timestamptz` na meia-noite; se as colunas já
-- estivessem convertidas e o predicado ainda comparasse com `current_date`, todo mandato/vínculo
-- encerrado passaria a valer um dia a mais, sem erro, na direção permissiva. Colunas,
-- constraints e funções vão neste arquivo só, nesta ordem.
--
-- ============================================================================
-- Passo 1 — enum novo e conferência de dependências pelo CATÁLOGO, não de memória.
-- Query rodada contra o banco local antes de escrever este arquivo:
--
--   select distinct dependente.relname, dependente.relkind
--     from pg_depend d
--     join pg_rewrite r on r.oid = d.objid
--     join pg_class dependente on dependente.oid = r.ev_class
--     join pg_class origem on origem.oid = d.refobjid
--    where origem.relname in ('papeis','vinculos')
--      and d.refobjsubid > 0;
--
-- Resultado medido (2026-09-06): UMA linha — vw_inadimplencia_nominal (view), usa `v.fim is
-- null`. Confirma a previsão do arquiteto; nenhuma outra dependente apareceu. Também confirmado
-- neste banco: `alter table vinculos alter column fim type timestamptz` falha com
-- "cannot alter type of a column used by a view or rule" enquanto a view existir — por isso o
-- drop abaixo, antes da conversão do passo 3, e o recreate no passo 6.
-- ============================================================================
create type public.motivo_fim_mandato as enum
  ('renuncia', 'substituicao', 'termino_de_mandato', 'erro_cadastral', 'conta_comprometida');

drop view public.vw_inadimplencia_nominal;

-- ============================================================================
-- Passo 2 — colunas novas em `papeis`: simetria com `vinculos`, que já tem `motivo_fim`.
-- `motivo_fim` é enum fechado, não texto livre — `papeis.motivo` (texto livre, na concessão)
-- está deliberadamente fora de `audit.colunas_liberadas` e sairia `[REDIGIDO]` na trilha; um
-- `motivo_fim` textual teria o mesmo destino no campo que existe para ser lido nela.
-- ============================================================================
alter table public.papeis
  add column encerrado_por uuid references public.pessoas(id),
  add column motivo_fim    public.motivo_fim_mandato,
  add constraint papeis_encerramento_ck
    check ((encerrado_por is null and motivo_fim is null) or mandato_fim is not null);

comment on column public.papeis.encerrado_por is
  'Quem encerrou o mandato. FK técnica (audit.colunas_liberadas). Só preenchível junto com '
  'mandato_fim (papeis_encerramento_ck) — mesma forma de vinculos.motivo_fim/vinculos.fim.';
comment on column public.papeis.motivo_fim is
  'Enum fechado, não texto livre (ADR-0030 §5): campo redigido na trilha se fosse texto livre, '
  'porque papeis.motivo está fora de audit.colunas_liberadas de propósito.';

-- ============================================================================
-- Passo 3 — conversão de tipo. É O PASSO QUE NÃO PODE SAIR ERRADO (ADR-0030 §Especificação).
--
-- ARMADILHA Nº1 do ADR: `using (coluna_fim + 1)::timestamptz`, NUNCA cast direto na ponta de
-- fim. O intervalo antigo era FECHADO: `fim = 2026-09-06` significa "vigente até o fim do dia
-- 06". O equivalente meia-aberto é `2026-09-07 00:00`. Um cast direto (`fim::timestamptz`)
-- gravaria `2026-09-06 00:00` e REVOGARIA RETROATIVAMENTE o dia inteiro de todo mundo — reescreve
-- o passado, a única coisa que este ADR se compromete a não fazer. `inicio`/`mandato_inicio`
-- convertem direto: a ponta inicial já era inclusiva nas duas semânticas.
-- ============================================================================

-- Contagem "antes", com o predicado ANTIGO (fechado, sobre colunas ainda `date`) — captura quem
-- é vigente hoje segundo a regra vigente até este exato ponto da migração.
-- "Hoje" é ancorado no fuso de negócio (America/Sao_Paulo), não no TimeZone da sessão que roda
-- a migração — pela MESMA razão do parágrafo abaixo: um `current_date` cru, aqui, compararia o
-- estado "antes" num referencial diferente do estado "depois" (que passa a ser fixado em
-- America/Sao_Paulo) sempre que a sessão não estiver nesse fuso, e a checagem de sanidade
-- poderia mentir (falso positivo OU falso negativo) numa janela de até 3h por dia.
create temporary table _adr0030_vigencia_antes as
select
  (select count(*) from public.papeis
    where mandato_inicio <= (now() at time zone 'America/Sao_Paulo')::date
      and (mandato_fim is null or mandato_fim >= (now() at time zone 'America/Sao_Paulo')::date)) as papeis,
  (select count(*) from public.vinculos
    where inicio <= (now() at time zone 'America/Sao_Paulo')::date
      and (fim is null or fim >= (now() at time zone 'America/Sao_Paulo')::date)) as vinculos;

-- FUSO EXPLÍCITO NA CONVERSÃO — achado do `auditor-rls` sobre a redação original do ADR-0030
-- passo 3, corrigido pelo arquiteto no próprio ADR. `(mandato_fim + 1)::timestamptz` (cast
-- direto) usa o `TimeZone` IMPLÍCITO da sessão que roda a migração. Local, hoje, é inofensivo
-- (banco em UTC de ponta a ponta, sem dado real — D2). No dia em que houver projeto hospedado, a
-- sessão que aplica a migração pode estar em UTC enquanto o app é America/Sao_Paulo — o cast
-- implícito estreitaria 3h a vigência de CADA linha, retroativamente: o "reescrever o passado"
-- que este ADR existe para não fazer, entrando pela porta que ninguém olhou. Referencial não
-- declarado é da mesma família de defeito que resolução errada (ADR-0030 §1, corolário): "hoje"
-- não pode depender de em que fuso a sessão que executa o SQL por acaso está.
--
-- O `::timestamp` intermediário NÃO é decorativo. `date` converte implicitamente tanto para
-- `timestamp` quanto para `timestamptz`; `date at time zone 'x'` sem o cast fica ambíguo para o
-- resolvedor de operadores e resolve para o par ERRADO (`timestamptz at time zone` — que
-- INTERPRETA a data como se já fosse um instante UTC e devolve o horário local correspondente,
-- na direção oposta à pretendida). Confirmado neste banco:
--   '2026-09-06'::date at time zone 'America/Sao_Paulo'             -> 2026-09-05 21:00:00 (ERRADO)
--   ('2026-09-06'::date)::timestamp at time zone 'America/Sao_Paulo' -> 2026-09-06 03:00:00+00 (CERTO)
-- Fixar `::timestamp` primeiro força o par certo (`timestamp at time zone` — interpreta a data
-- como meia-noite LOCAL em `zone` e devolve o instante UTC correspondente) e torna a expressão
-- determinística, não dependente de qual delas o resolvedor prefere numa versão de Postgres.

-- papeis
alter table public.papeis alter column mandato_inicio drop default;
alter table public.papeis alter column mandato_inicio type timestamptz
  using (mandato_inicio::timestamp at time zone 'America/Sao_Paulo'); -- meia-noite LOCAL do próprio dia
alter table public.papeis alter column mandato_inicio set default now();

alter table public.papeis alter column mandato_fim type timestamptz
  using ((mandato_fim + 1)::timestamp at time zone 'America/Sao_Paulo'); -- meia-noite LOCAL do dia SEGUINTE

-- vinculos: idêntico, em inicio e fim.
alter table public.vinculos alter column inicio drop default;
alter table public.vinculos alter column inicio type timestamptz
  using (inicio::timestamp at time zone 'America/Sao_Paulo');
alter table public.vinculos alter column inicio set default now();

alter table public.vinculos alter column fim type timestamptz
  using ((fim + 1)::timestamp at time zone 'America/Sao_Paulo');

-- Sanidade, na MESMA transação (o arquivo inteiro é uma transação implícita do protocolo simples
-- de query — nenhum BEGIN/COMMIT explícito é necessário nem foi adicionado): "ninguém perde nem
-- ganha vigência hoje". Se qualquer contagem divergir, aborta a migração inteira.
do $$
declare
  v_antes record;
  v_papeis_depois   bigint;
  v_vinculos_depois bigint;
begin
  select * into v_antes from _adr0030_vigencia_antes;

  select count(*) into v_papeis_depois from public.papeis
   where mandato_inicio <= now() and (mandato_fim is null or mandato_fim > now());
  select count(*) into v_vinculos_depois from public.vinculos
   where inicio <= now() and (fim is null or fim > now());

  if v_papeis_depois <> v_antes.papeis then
    raise exception
      'ADR-0030: a contagem de papeis vigentes mudou na conversão de tipo (antes=%, depois=%) — '
      'abortando para não revogar nem estender vigência de ninguém retroativamente.',
      v_antes.papeis, v_papeis_depois;
  end if;

  if v_vinculos_depois <> v_antes.vinculos then
    raise exception
      'ADR-0030: a contagem de vinculos vigentes mudou na conversão de tipo (antes=%, depois=%) '
      '— abortando para não revogar nem estender vigência de ninguém retroativamente.',
      v_antes.vinculos, v_vinculos_depois;
  end if;
end $$;

drop table _adr0030_vigencia_antes;

-- ============================================================================
-- Passo 4 — constraints e comentários. `papeis_mandato_ck` e `vinculos_periodo_ck` sobrevivem
-- (`>=` continua válido para timestamptz) sem precisar de drop/create; o que muda é o
-- SIGNIFICADO, registrado em comment explícito.
-- ============================================================================
comment on constraint papeis_mandato_ck on public.papeis is
  'ADR-0030: intervalo de vigência é MEIA-ABERTO [mandato_inicio, mandato_fim) em instante, não '
  'período fechado em dias. mandato_fim = mandato_inicio é intervalo VAZIO e legítimo: registra '
  'concessão desfeita no mesmo instante em que começou, sem nunca ter tido efeito.';
comment on constraint vinculos_periodo_ck on public.vinculos is
  'ADR-0030: intervalo de vigência é MEIA-ABERTO [inicio, fim) em instante, não período fechado '
  'em dias. fim = inicio é intervalo VAZIO e legítimo: registra vínculo desfeito no mesmo '
  'instante em que começou, sem nunca ter tido efeito.';

comment on column public.papeis.mandato_inicio is
  'ADR-0030: instante (timestamptz) em que o mandato começa a valer, ponta INCLUSIVA do '
  'intervalo [mandato_inicio, mandato_fim). Antes de 2026-09-06 era `date` com semântica de dia '
  'fechado — ver ADR-0030 para a conversão e a garantia de que nenhum mandato existente mudou de '
  'vigência.';
comment on column public.papeis.mandato_fim is
  'ADR-0030: instante (timestamptz) em que o mandato deixa de valer, ponta EXCLUSIVA do '
  'intervalo [mandato_inicio, mandato_fim) — "cessar agora" é `mandato_fim = now()`, aceito e '
  'efetivo no mesmo instante. Antes de 2026-09-06 era `date` com semântica de dia fechado '
  '(`fim >= current_date`); a conversão preservou a vigência de toda linha existente (ver '
  'sanidade da migração de conversão).';
comment on column public.vinculos.inicio is
  'ADR-0030: instante (timestamptz) em que o vínculo começa a valer, ponta INCLUSIVA do '
  'intervalo [inicio, fim). Antes de 2026-09-06 era `date` com semântica de dia fechado.';
comment on column public.vinculos.fim is
  'ADR-0030: instante (timestamptz) em que o vínculo deixa de valer, ponta EXCLUSIVA do '
  'intervalo [inicio, fim) — "cessar agora" é `fim = now()`, aceito e efetivo no mesmo instante. '
  'Antes de 2026-09-06 era `date` com semântica de dia fechado (`fim >= current_date`); a '
  'conversão preservou a vigência de toda linha existente. O parecer off-boarding-ex-morador.md '
  'trata `fim` como o fato datado do encerramento — continua tratando: a tradução de "encerra no '
  'dia D" grava (D+1) à meia-noite em fuso explícito (ADR-0030 §3), reproduzindo bit a bit o '
  'comportamento anterior para saída planejada.';

-- ============================================================================
-- Passo 5 — funções. Em todas: `current_date` -> `now()`, `fim >= …` -> `fim > …`.
--
-- ARMADILHA Nº2 do ADR: `eh_editor_vigente_linha` muda de assinatura (parâmetros 2 e 3 de
-- `date` para `timestamptz`). `create or replace` NÃO substitui uma assinatura diferente — cria
-- SOBRECARGA, deixando a versão `date` viva; os dois triggers (que não mudam de corpo, só
-- chamam esta função) resolveriam por nome e poderiam ligar na antiga, que compararia
-- `timestamptz` promovido contra `current_date` e erraria em silêncio na guarda do último
-- editor (D9/V10). `drop function` explícito da assinatura antiga é obrigatório.
-- ============================================================================
drop function if exists public.eh_editor_vigente_linha(public.papel, date, date, boolean);

create function public.eh_editor_vigente_linha(
  p_papel public.papel, p_mandato_inicio timestamptz, p_mandato_fim timestamptz, p_pessoa_ativa boolean
) returns boolean language sql stable as $$
  select p_pessoa_ativa
     and p_papel = 'editor'
     and p_mandato_inicio <= now()
     and (p_mandato_fim is null or p_mandato_fim > now())
$$;

comment on function public.eh_editor_vigente_linha(public.papel, timestamptz, timestamptz, boolean) is
  'Predicado único de "esta linha de papeis conta como editor vigente" (evita duplicar a fórmula '
  'nos dois triggers de guarda do último editor). ADR-0030: intervalo meia-aberto em instante, '
  '`now()` — nunca `clock_timestamp()`, para continuar STABLE. Esta função foi recriada com nova '
  'assinatura (parâmetros 2 e 3 agora timestamptz); a versão `date` foi explicitamente DROPADA '
  '(não substituída) para não deixar sobrecarga viva — ver ADR-0030, armadilha nº2.';

-- Os corpos de tg_pessoas_impede_autotranca_editor e tg_papeis_impede_fim_ultimo_editor NÃO
-- mudam: só chamam eh_editor_vigente_linha(pa.papel, pa.mandato_inicio, pa.mandato_fim, ...),
-- e pa.mandato_inicio/pa.mandato_fim já são timestamptz depois do passo 3 — resolvem para a
-- única sobrecarga que sobrou. Não são tocados aqui.

-- PRIMITIVA de RLS. Papel vale se: mandato vigente (agora [inicio, fim) em instante) E, para
-- editor/conselho, sessão em AAL2.
create or replace function app.tem_papel(p public.papel)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1
      from public.papeis pa
      join public.pessoas pe on pe.id = pa.pessoa_id
     where pe.auth_user_id = auth.uid()
       and pe.ativa
       and pa.papel = p
       and pa.mandato_inicio <= now()
       and (pa.mandato_fim is null or pa.mandato_fim > now())
       -- TOTP obrigatório para papel privilegiado (ADR-0003 item 5):
       and ( p = 'morador'
             or coalesce(auth.jwt() ->> 'aal', 'aal1') = 'aal2' )
  )
$$;

comment on function app.tem_papel(public.papel) is
  'PRIMITIVA de RLS. Nenhuma policy verifica papel de outro jeito — nem por app_metadata, nem '
  'reescrevendo este predicado (ADR-0012). ADR-0030: vigência é intervalo meia-aberto em '
  'instante — `mandato_inicio <= now() and (mandato_fim is null or mandato_fim > now())`, nunca '
  '`current_date`/`>=` (INV-14).';

-- `ativa` E (vínculo vigente OU papel vigente) — ver V8 no arquivo baseline para o motivo do
-- "OU papel vigente" (editor única e conselheiros sem vínculo de unidade).
create or replace function app.eh_autenticado()
returns boolean language sql stable security definer set search_path = '' as $$
  select
    app.pessoa_atual() is not null
    and (
      exists (
        select 1 from public.vinculos v
         where v.pessoa_id = app.pessoa_atual()
           and v.inicio <= now()
           and (v.fim is null or v.fim > now())
      )
      or exists (
        select 1 from public.papeis pa
         where pa.pessoa_id = app.pessoa_atual()
           and pa.mandato_inicio <= now()
           and (pa.mandato_fim is null or pa.mandato_fim > now())
      )
    )
$$;

-- Unidades da pessoa logada, por vínculo vigente.
create or replace function app.unidades_da_pessoa()
returns setof uuid language sql stable security definer set search_path = '' as $$
  select v.unidade_id
    from public.vinculos v
   where v.pessoa_id = app.pessoa_atual()
     and v.inicio <= now()
     and (v.fim is null or v.fim > now())
$$;

-- app.pessoa_atual(), app.eh_editor(), app.eh_gestao(), app.papel_atual() não mudam: nenhuma
-- delas compara período diretamente (ADR-0030 §Especificação, passo 5).

-- ============================================================================
-- Passo 6 — recriar a view derrubada no passo 1 (corpo idêntico — `v.fim is null` continua
-- correto sob a nova semântica), com os mesmos GRANTs, e a lista de auditoria.
-- ============================================================================
create view public.vw_inadimplencia_nominal
with (security_invoker = true) as
select
  c.unidade_id,
  u.bloco,
  u.numero,
  v.pessoa_id,
  p.nome as pessoa_nome,
  c.competencia,
  c.valor_centavos,
  c.valor_pago_centavos,
  c.status,
  c.vencimento
from public.cobrancas c
join public.unidades u on u.id = c.unidade_id
left join public.vinculos v on v.unidade_id = c.unidade_id
  and v.tipo = 'proprietario' and v.fim is null
left join public.pessoas p on p.id = v.pessoa_id
where c.status in ('atrasada', 'acordo');

comment on view public.vw_inadimplencia_nominal is
  'Leitura nominal por gestão PRECISA gerar audit.acesso (SPEC §5.5) — a cargo da rotina de '
  'servidor que consulta esta view, não da view em si (não existe "AFTER SELECT" em SQL). '
  'Recriada pelo ADR-0030 (vinculos.fim mudou de date para timestamptz) — corpo idêntico.';

revoke all on public.vw_inadimplencia_nominal from public, anon, authenticated, service_role;
grant select on public.vw_inadimplencia_nominal to authenticated;

-- audit.colunas_liberadas: colunas novas de papeis, liberadas pelo mesmo critério já aplicado a
-- vinculos.motivo_fim ("valor de enum fechado, não texto livre"). Sem isso a trilha mostra
-- [REDIGIDO] exatamente no campo que existe para ser lido nela.
insert into audit.colunas_liberadas (tabela, coluna, motivo) values
  ('papeis', 'encerrado_por', 'FK técnica'),
  ('papeis', 'motivo_fim', 'valor de enum fechado, não texto livre');

-- As quatro colunas convertidas deixam de ser "data técnica": passam a ser instante técnico —
-- janela de autorização (ADR-0030, Especificação, passo 6).
update audit.colunas_liberadas
   set motivo = 'instante técnico — janela de autorização (ADR-0030)'
 where (tabela, coluna) in (
   ('papeis', 'mandato_inicio'),
   ('papeis', 'mandato_fim'),
   ('vinculos', 'inicio'),
   ('vinculos', 'fim')
 );

-- ============================================================================
-- INV-14 (nova, ADR-0030): nenhuma função de autorização compara período de vigência com
-- `current_date`. Varredura por catálogo, para não depender de lembrar de checar manualmente
-- toda vez que uma função nova entrar no schema `app`.
--
-- ALCANCE (achado do `auditor-rls`): uma varredura que só olha `pronamespace = app` NÃO alcança
-- `public.eh_editor_vigente_linha` — que mora em `public` de propósito (ver comentário no passo
-- 5) e é EXATAMENTE onde a sobrecarga `date` da armadilha nº2 sobreviveria se o `drop function`
-- acima tivesse falhado silenciosamente. Uma varredura que protege tudo menos o caso que
-- motivou a trava não vale o nome de sentinela — por isso o segundo alcance abaixo, nomeado, em
-- vez de alargar o filtro de schema (que pegaria ruído de funções de `public` sem relação
-- nenhuma com autorização, ex.: `current_date` em lançamento/cobrança).
-- ============================================================================
do $$
declare
  v_ofensor text;
  v_oid     oid;
begin
  -- Alcance 1: qualquer função do schema app que ainda compare vigência com current_date.
  -- Restringe por `pronamespace` com subquery escalar (não por JOIN + filtro de nome) de
  -- propósito: um JOIN deixa o planner livre para avaliar `pg_get_functiondef(p.oid)` em
  -- qualquer linha de pg_proc antes do filtro de schema — inclusive em agregados do
  -- pg_catalog (ex.: array_agg), para os quais pg_get_functiondef() ERRA com "is an aggregate
  -- function" (42809). A subquery escalar dá ao planner uma condição de igualdade sobre
  -- `pronamespace` que restringe as linhas MAIS CEDO. Reproduzido e confirmado neste banco.
  select p.proname into v_ofensor
    from pg_proc p
   where p.pronamespace = (select oid from pg_namespace where nspname = 'app')
     and pg_get_functiondef(p.oid) ilike '%current_date%'
   limit 1;

  -- Alcance 2: public.eh_editor_vigente_linha, nomeada explicitamente. `to_regprocedure` com a
  -- assinatura exata resolve para um OID único sem varrer pg_proc — mesma cautela do alcance 1,
  -- por outro caminho.
  if v_ofensor is null then
    v_oid := to_regprocedure(
      'public.eh_editor_vigente_linha(public.papel, timestamptz, timestamptz, boolean)');
    if v_oid is not null and pg_get_functiondef(v_oid) ilike '%current_date%' then
      v_ofensor := 'eh_editor_vigente_linha';
    end if;
  end if;

  if v_ofensor is not null then
    raise exception
      'ADR-0030/INV-14: função % ainda compara vigência com current_date — deveria usar '
      'now() (intervalo meia-aberto em instante).', v_ofensor;
  end if;
end $$;
