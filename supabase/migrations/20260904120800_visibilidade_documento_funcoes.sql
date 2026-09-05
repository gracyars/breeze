-- Breeze — baseline 08: predicado de visibilidade de documento/página.
-- ****************************************************************************
-- FUNÇÕES CRÍTICAS — ARMADILHA Nº 1 DO PROJETO (SPEC §7, §8.1).
-- Regra de visibilidade em UM lugar só, com a invariante do PISO (ADR-0019/D13) e o princípio de
-- PREDICADO LOCAL (ADR-0023/D16, 2026-09-04) governando a forma:
--
--   app.ordem_visibilidade(nivel)            -- ranking de PERMISSIVIDADE, não de "força do
--                                                nome": conselho(0) < restrito(1) < autenticado(2)
--                                                < publico(3). `restrito` é MAIS permissivo que
--                                                `conselho` porque soma a unidade vinculada à
--                                                gestão — inverter os dois é o erro mais fácil
--                                                de cometer aqui, e o mais caro.
--   app.nivel_visivel(nivel, documento_id)   -- dado um NÍVEL de exposição já resolvido, este
--                                                papel enxerga? NÚCLEO ÚNICO do mapeamento
--                                                nível → papel. Nada mais reescreve isto.
--   app.nivel_efetivo(documento_id, pagina)  -- qual É o nível efetivo desta página? SÓ
--                                                `coalesce(documento_paginas.visibilidade,
--                                                documentos.visibilidade)` — override explícito
--                                                da própria página, ou herança do PISO do próprio
--                                                documento. Lê só a linha avaliada e a linha que
--                                                a define por FK. NÃO existe mais conceito de
--                                                "documento misto" aqui (ver ADR-0023/D16: havia
--                                                um `exists` sobre outras páginas do mesmo
--                                                documento — não-local, modal, e foi ele que
--                                                vazou na 3ª rodada do auditor-rls).
--   app.documento_visivel(documento_id)      -- linha/arquivo INTEIRO (documentos, storage do
--                                                bucket 'documentos'). Com o piso garantido por
--                                                trigger (documento_paginas_valida_piso +
--                                                documentos_valida_piso_paginas, os dois lados),
--                                                este nível é sempre o MAIS RESTRITIVO de todo o
--                                                documento — herdar o padrão do documento para
--                                                quem baixa o arquivo cru é seguro POR CONSTRUÇÃO.
--   app.pagina_visivel(documento_id, pagina) -- conteúdo POR PÁGINA (documento_paginas, chunks,
--                                                deliberacoes).
--
-- Nenhuma policy, em nenhuma tabela, reescreve o predicado — todas chamam uma destas funções de
-- entrada (documento_visivel / pagina_visivel). Predicado copiado diverge, e diverge calado.
--
-- PRINCÍPIO (ADR-0023, "predicado de autorização deve ser local"): o valor de um predicado de
-- autorização só pode depender da linha avaliada, das linhas que a definem por FK, e do sujeito
-- da sessão — de mais nada. Quando depende de OUTRAS linhas (um `exists`/`count` sobre uma
-- coleção), toda escrita naquelas linhas vira uma mudança de autorização que ninguém chamou de
-- "grant". `app.nivel_visivel` usa `exists` sobre `documento_unidades` no ramo `restrito` — isso
-- é FK constitutiva (a própria decisão de "quem vê"), não modal, e por isso fica. Se algum dia
-- este arquivo ganhar outro `exists`/`count`/`min`/`max` dentro de uma função chamada por
-- policy, classifique a espécie antes de aceitar (constitutiva: mantenha e guarde; modal: torne
-- local — nunca monotonize por padrão, monotonizar é só o degrau de última instância).
-- ****************************************************************************

-- Ranking de PERMISSIVIDADE. IMMUTABLE e pura — sem acesso a tabela, sem stateful. O nome do
-- enum NÃO segue a ordem (é a armadilha, ADR-0019/D13): `restrito` soma a unidade vinculada à
-- gestão de `conselho`, então é estritamente mais permissivo, mesmo "parecendo" mais fechado.
create or replace function app.ordem_visibilidade(p_visibilidade public.visibilidade_documento)
returns int language sql immutable as $$
  select case p_visibilidade
    when 'conselho'    then 0
    when 'restrito'    then 1
    when 'autenticado' then 2
    when 'publico'     then 3
  end
$$;

-- Dado um nível de exposição já resolvido, este papel enxerga? NULL (página sem classificação
-- num documento com override em outra página) cai no ELSE => false — fail closed. Mantido por
-- conservadorismo mesmo depois do piso (ADR-0019/D13): não é mais o que sustenta o modelo, mas
-- continua sendo a postura correta diante de dado não classificado.
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

-- Nível efetivo de UMA página — LOCAL (ADR-0023/D16): override explícito da própria página, ou
-- herança do piso do documento. Nada mais.
--
-- Removido nesta migração o ramo "documento tem override em OUTRA página -> página sem
-- classificação própria não herda nada (fail closed)". Não era defesa: era o próprio vazamento.
-- Sob a invariante do piso (ADR-0019), todo override já é >= documentos.visibilidade — herdar o
-- piso para a página sem override nunca pode afrouxar, é seguro por construção. O ramo removido
-- dependia de um `exists` sobre TODAS as páginas do documento (não-local, espécie modal): a
-- página 5 tinha seu nível decidido pela existência de override na página 3, e apagar a página 3
-- abria a página 5 sozinha — vazamento real, achado pelo auditor-rls na 3ª rodada. O mesmo
-- predicado errava também na direção oposta: num documento `publico` (o teto), o único override
-- possível é `publico` — um no-op — e marcá-lo fechava todas as OUTRAS páginas por engano.
-- Consertar monotonizando (flag que só liga) teria fechado o vazamento e mantido essa anomalia
-- inversa; a decisão foi eliminar o conceito de "documento misto" inteiro, não corrigi-lo.
create or replace function app.nivel_efetivo(p_documento_id uuid, p_pagina int)
returns public.visibilidade_documento language sql stable security definer set search_path = '' as $$
  select coalesce(dp.visibilidade, d.visibilidade)
    from public.documentos d
    left join public.documento_paginas dp
      on dp.documento_id = d.id and dp.pagina = p_pagina
   where d.id = p_documento_id
$$;

-- Linha/arquivo inteiro. Usado por: documentos (select), storage.objects do bucket 'documentos'
-- (o PDF cru não é fatiado por página — baixar o arquivo inteiro continua gated pelo nível do
-- DOCUMENTO, não da página; a granularidade por página vale para texto extraído/busca/citação).
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

-- Conteúdo POR PÁGINA. Usado por: documento_paginas (select), chunks (select, pela pagina_ini),
-- deliberacoes (quando há página citada). Resolve herança/override via app.nivel_efetivo().
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

revoke all on function
  app.ordem_visibilidade(public.visibilidade_documento),
  app.nivel_visivel(public.visibilidade_documento, uuid),
  app.nivel_efetivo(uuid, int),
  app.documento_visivel(uuid),
  app.pagina_visivel(uuid, int)
from public, anon, authenticated;

grant execute on function
  app.ordem_visibilidade(public.visibilidade_documento),
  app.nivel_visivel(public.visibilidade_documento, uuid),
  app.nivel_efetivo(uuid, int),
  app.documento_visivel(uuid),
  app.pagina_visivel(uuid, int)
to authenticated;
-- documento_visivel/pagina_visivel/ordem_visibilidade também precisam de EXECUTE para `anon`
-- (documento e página públicos, sem login — inclusive página pública dentro de documento não-
-- público, ex.: o regimento embutido numa ata autenticada).
grant execute on function
  app.documento_visivel(uuid), app.pagina_visivel(uuid, int), app.ordem_visibilidade(public.visibilidade_documento)
to anon;

comment on function app.pagina_visivel(uuid, int) is
  'Entrada de RLS para conteúdo por página (correção 2026-09-04, docs/inventario-acervo.md; piso '
  'de permissividade ADR-0019/D13). Resolve herança via app.nivel_efetivo() e aplica '
  'app.nivel_visivel() — nenhuma tabela reescreve este predicado (armadilha nº1, SPEC §7).';
comment on function app.ordem_visibilidade(public.visibilidade_documento) is
  'ADR-0019/D13: conselho(0) < restrito(1) < autenticado(2) < publico(3). A ordem NÃO segue a '
  'leitura ingênua do nome do enum — restrito soma a unidade vinculada à gestão de conselho, '
  'logo é mais permissivo. Inverter isto permite página conselho dentro de documento restrito, '
  'baixável pela unidade vinculada.';

-- ============================================================================
-- Trigger de PISO (ADR-0019/D13, achado V3): documentos.visibilidade é o mínimo de
-- permissividade do documento inteiro. Uma página só pode ser IGUAL ou MAIS PERMISSIVA que o
-- documento — nunca mais restritiva. Rebaixar o documento como efeito colateral de classificar
-- uma página tornaria a coluna não-declarativa (a editora define, o sistema muda por baixo) e
-- brigaria com o trigger documentos_valida_visibilidade (permite_publico). Por isso este trigger
-- DÁ ERRO, nunca sobrescreve em silêncio.
-- ============================================================================
create or replace function public.tg_documento_paginas_valida_piso()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_doc_visibilidade public.visibilidade_documento;
begin
  if new.visibilidade is null then
    return new; -- sem override, nada a validar contra o piso
  end if;

  select d.visibilidade into v_doc_visibilidade
    from public.documentos d where d.id = new.documento_id;

  if v_doc_visibilidade is null then
    raise exception 'documento_id % não existe em documentos', new.documento_id;
  end if;

  if app.ordem_visibilidade(new.visibilidade) < app.ordem_visibilidade(v_doc_visibilidade) then
    raise exception
      'Página % do documento % não pode ter visibilidade "%" mais restritiva que o piso do '
      'documento ("%"). documentos.visibilidade é o piso — a página só pode ser IGUAL ou MAIS '
      'permissiva (ADR-0019/D13, ordem: conselho < restrito < autenticado < publico).',
      new.pagina, new.documento_id, new.visibilidade, v_doc_visibilidade;
  end if;

  return new;
end $$;

create trigger documento_paginas_valida_piso
  before insert or update of visibilidade, documento_id on public.documento_paginas
  for each row execute function public.tg_documento_paginas_valida_piso();

-- ============================================================================
-- Trigger de sincronização de `documentos.tem_paginas_mistas` — PURAMENTE INFORMATIVO/CURADORIA
-- desde ADR-0023/D16. Liga a flag sozinha assim que a primeira página ganha override; a editora
-- ainda pode ligá-la antes, para declarar intenção cedo. Nunca desliga sozinha.
-- ADR-0023/D16: esta coluna NUNCA participou de decisão de segurança por si só (não é lida por
-- nenhuma policy), mas o CONCEITO que ela representava ("documento misto") existiu também como
-- predicado derivado em app.nivel_efetivo() via app.documento_tem_override() — removido nesta
-- mesma migração por ser não-local (um `exists` sobre outras páginas do documento). A lição
-- registrada no ADR: "sempre derivar" não elimina a dependência de outras linhas, só muda o dono
-- dela — de um humano que esquece de marcar a flag, para outras linhas que mudam depois. A
-- resposta certa não era a flag nem o derivado: era não precisar do conceito. `tem_paginas_mistas`
-- sobrevive só como sinal de UI/curadoria, e este trigger só existe para mantê-la coerente com
-- essa finalidade — nada mais depende dela.
-- ============================================================================
create or replace function public.tg_documento_paginas_sincroniza_flag_mista()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_doc_id uuid := coalesce(new.documento_id, old.documento_id);
begin
  if (tg_op in ('INSERT','UPDATE') and new.visibilidade is not null) then
    update public.documentos
       set tem_paginas_mistas = true
     where id = v_doc_id and not tem_paginas_mistas;
  end if;
  return coalesce(new, old);
end $$;

create trigger documento_paginas_sincroniza_flag_mista
  after insert or update of visibilidade on public.documento_paginas
  for each row execute function public.tg_documento_paginas_sincroniza_flag_mista();

-- ****************************************************************************
-- CLASSE DE DEFEITO (V1-R/V3-R, auditor-rls, 2ª rodada): "a invariante é validada na escrita de
-- um lado da relação e não é revalidada quando o outro lado muda." Os dois triggers de piso
-- acima (documento_paginas_valida_piso) e de uniformidade de chunk (mais abaixo,
-- chunks_valida_visibilidade_uniforme) só disparam quando a LINHA QUE ELES PROTEGEM é escrita —
-- nenhum dos dois revalida quando a linha do OUTRO LADO muda depois:
--   V1-R: chunk é validado uniforme ao ser criado; documento_paginas.visibilidade muda DEPOIS
--         (ordem real do pipeline: worker chunkiza primeiro, curadoria classifica a página
--         depois) e o chunk já existente nunca é reavaliado — texto de página agora restrita
--         vaza pela busca via um chunk cujo pagina_ini ainda resolve como permissivo.
--   V3-R: página é validada contra o piso do documento ao ganhar override; documentos.visibilidade
--         muda DEPOIS (subir a visibilidade do documento) e a página com override mais restritivo
--         nunca é revalidada — a linha do documento e o PDF cru (storage, gate por
--         app.documento_visivel) passam a ficar visíveis a quem não deveria ver a página presa
--         dentro dele.
-- Os dois ganham o trigger que faltava, no lado que faltava. Mecanismo NÃO é o mesmo dos dois
-- lados de propósito: reclassificar uma página é o fluxo de curadoria que motivou o modelo
-- inteiro (SPEC §3, embutido/regimento) — bloquear isso destruiria o próprio caso de uso; então
-- V1-R invalida (apaga) o chunk agora inconsistente, e o worker o recria no próximo
-- reprocessamento (idempotente, SPEC §3). Já subir documentos.visibilidade é ação humana rara e
-- deliberada, sem fluxo automático que dependa dela funcionar sem confirmação — então V3-R
-- BLOQUEIA com erro explícito, do mesmo jeito que o piso já bloqueia do outro lado.
-- ****************************************************************************

-- V1-R: quando uma página ganha/perde override, invalida (apaga) qualquer chunk existente cujo
-- intervalo [pagina_ini, pagina_fim] toque essa página e tenha deixado de ser uniforme. Não
-- bloqueia a reclassificação — apagar o chunk é auto-corretivo, o worker reindexa.
create or replace function public.tg_documento_paginas_invalida_chunks_afetados()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_doc_id uuid := coalesce(new.documento_id, old.documento_id);
  v_pagina int := coalesce(new.pagina, old.pagina);
begin
  delete from public.chunks c
   where c.documento_id = v_doc_id
     and v_pagina between c.pagina_ini and c.pagina_fim
     and (
       select count(distinct coalesce(app.nivel_efetivo(c.documento_id, g.p)::text, '(nulo)'))
         from generate_series(c.pagina_ini, c.pagina_fim) g(p)
     ) > 1;
  return coalesce(new, old);
end $$;

create trigger documento_paginas_invalida_chunks_afetados
  after insert or update of visibilidade on public.documento_paginas
  for each row execute function public.tg_documento_paginas_invalida_chunks_afetados();

comment on function public.tg_documento_paginas_invalida_chunks_afetados() is
  'V1-R (auditor-rls): fecha a variante temporal do achado V1 — reclassificar uma página DEPOIS '
  'que o chunk já existe não deixava rastro nenhum antes desta trigger. Apaga, nunca bloqueia: '
  'bloquear quebraria o fluxo de curadoria (classificar o regimento embutido é o caso de uso '
  'central do modelo). Reprocessamento é idempotente (SPEC §3) — o worker recria o chunk certo.';

-- V3-R: quando documentos.visibilidade SOBE (fica mais permissiva), revalida que nenhuma página
-- já classificada ficou mais restritiva que o novo piso. Aqui BLOQUEIA — ao contrário de V1-R,
-- não há fluxo automático que dependa de elevar visibilidade de documento funcionar sem
-- confirmação humana, e a página presa dentro do PDF cru (storage) tornaria a ação irreversível
-- em silêncio se só sobrescrevesse.
create or replace function public.tg_documentos_valida_piso_paginas()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_pagina public.documento_paginas;
begin
  if new.visibilidade = old.visibilidade then
    return new;
  end if;

  select dp.* into v_pagina
    from public.documento_paginas dp
   where dp.documento_id = new.id
     and dp.visibilidade is not null
     and app.ordem_visibilidade(dp.visibilidade) < app.ordem_visibilidade(new.visibilidade)
   limit 1;

  if found then
    raise exception
      'Não é possível mudar documentos.visibilidade (id %) de "%" para "%": a página % já tem '
      'override "%", mais restritivo que o novo piso (ADR-0019/D13, V3-R — a mesma regra de '
      'documento_paginas_valida_piso, agora do lado do documento). O PDF cru (storage) ficaria '
      'acessível a quem não deveria ver essa página. Reclassifique ou remova o override da '
      'página antes de mudar a visibilidade do documento.',
      new.id, old.visibilidade, new.visibilidade, v_pagina.pagina, v_pagina.visibilidade;
  end if;

  return new;
end $$;

create trigger documentos_valida_piso_paginas
  before update of visibilidade on public.documentos
  for each row execute function public.tg_documentos_valida_piso_paginas();

comment on function public.tg_documentos_valida_piso_paginas() is
  'V3-R (auditor-rls): fecha a variante temporal do achado V3 — o piso (ADR-0019/D13) só era '
  'validado quando a PÁGINA ganhava override; mudar documentos.visibilidade depois nunca '
  'revalidava as páginas já classificadas. Mesma classe de defeito do V1-R, mecanismo diferente '
  'de propósito: aqui bloqueia, porque não há fluxo automático que dependa de elevar '
  'visibilidade de documento sem confirmação humana.';

-- ============================================================================
-- Trigger de consistência de chunk (V1, auditor-rls — corrigido para NÃO depender de flag
-- nenhuma): um chunk não pode cobrir páginas de níveis de visibilidade EFETIVA diferentes —
-- roda SEMPRE, em todo documento, não só quando alguma flag está ligada. Antes desta correção,
-- o trigger só validava com tem_paginas_mistas=true, e nada obrigava a flag a estar certa —
-- resultado: chunk ancorado em página pública entregava o texto da página restrita seguinte,
-- pela busca, com a chave `anon`, sem login (achado real do auditor-rls, teste E2/E3 de
-- 01_visibilidade_documento_pagina_chunk_rls.sql).
-- ============================================================================
create or replace function public.tg_chunks_valida_visibilidade_uniforme()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_distintos int;
begin
  select count(distinct coalesce(app.nivel_efetivo(new.documento_id, g.p)::text, '(nulo)'))
    into v_distintos
    from generate_series(new.pagina_ini, new.pagina_fim) g(p);

  if v_distintos > 1 then
    raise exception
      'Chunk (documento %, páginas %-%) cobre páginas com visibilidade efetiva diferente — '
      'inclusive, possivelmente, página sem classificação num documento com override em outra '
      'página. Ancorar em pagina_ini vazaria (ou esconderia incorretamente) o resto do intervalo '
      '(V1, auditor-rls).', new.documento_id, new.pagina_ini, new.pagina_fim;
  end if;

  return new;
end $$;

create trigger chunks_valida_visibilidade_uniforme
  before insert or update of documento_id, pagina_ini, pagina_fim on public.chunks
  for each row execute function public.tg_chunks_valida_visibilidade_uniforme();
