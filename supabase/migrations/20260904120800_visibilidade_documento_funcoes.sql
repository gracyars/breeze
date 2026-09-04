-- Breeze — baseline 08: predicado de visibilidade de documento/página.
-- ****************************************************************************
-- FUNÇÕES CRÍTICAS — ARMADILHA Nº 1 DO PROJETO (SPEC §7, §8.1).
-- Regra de visibilidade em UM lugar só, agora em duas camadas porque um PDF pode conter mais de
-- uma visibilidade (correção do orquestrador, 2026-09-04, docs/inventario-acervo.md):
--
--   app.nivel_visivel(nivel, documento_id)   -- dado um NÍVEL de exposição já resolvido, este
--                                                papel enxerga? (publico/autenticado/conselho/
--                                                restrito). NÚCLEO ÚNICO do mapeamento
--                                                nível → papel. Nada mais reescreve isto.
--   app.nivel_efetivo(documento_id, pagina)  -- qual É o nível efetivo desta página? Resolve
--                                                herança: documento_paginas.visibilidade (se
--                                                setada) OU documentos.visibilidade — EXCETO
--                                                quando documentos.tem_paginas_mistas = true,
--                                                caso em que página sem classificação própria
--                                                NÃO herda o padrão do documento (falha fechado,
--                                                nunca aberto).
--   app.documento_visivel(documento_id)      -- linha/arquivo INTEIRO (documentos, storage do
--                                                bucket 'documentos' — o PDF cru não é fatiado
--                                                por página). Inalterado na semântica.
--   app.pagina_visivel(documento_id, pagina) -- conteúdo POR PÁGINA (documento_paginas, chunks,
--                                                deliberacoes). NOVO — é o que a correção exige.
--
-- Nenhuma policy, em nenhuma tabela, reescreve o predicado — todas chamam uma destas duas
-- funções de entrada (documento_visivel / pagina_visivel). Predicado copiado diverge, e diverge
-- calado.
-- ****************************************************************************

-- Dado um nível de exposição já resolvido, este papel enxerga? NULL (página sem classificação
-- num documento misto) cai no ELSE => false — fail closed.
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

-- Nível efetivo de UMA página: override explícito da página, ou herança do documento — exceto
-- em documento marcado tem_paginas_mistas, onde página sem override não herda nada (NULL).
create or replace function app.nivel_efetivo(p_documento_id uuid, p_pagina int)
returns public.visibilidade_documento language sql stable security definer set search_path = '' as $$
  select case when d.tem_paginas_mistas then dp.visibilidade
              else coalesce(dp.visibilidade, d.visibilidade)
         end
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
  app.nivel_visivel(public.visibilidade_documento, uuid),
  app.nivel_efetivo(uuid, int),
  app.documento_visivel(uuid),
  app.pagina_visivel(uuid, int)
from public, anon, authenticated;

grant execute on function
  app.nivel_visivel(public.visibilidade_documento, uuid),
  app.nivel_efetivo(uuid, int),
  app.documento_visivel(uuid),
  app.pagina_visivel(uuid, int)
to authenticated;
-- documento_visivel/pagina_visivel também precisam de EXECUTE para `anon` (documento e página
-- públicos, sem login — inclusive página pública dentro de documento não-público, ex.: o
-- regimento embutido numa ata autenticada).
grant execute on function app.documento_visivel(uuid), app.pagina_visivel(uuid, int) to anon;

comment on function app.pagina_visivel(uuid, int) is
  'Entrada de RLS para conteúdo por página (correção 2026-09-04, docs/inventario-acervo.md). '
  'Resolve herança via app.nivel_efetivo() e aplica app.nivel_visivel() — nenhuma tabela '
  'reescreve este predicado (armadilha nº1, SPEC §7).';

-- ============================================================================
-- Trigger de consistência: um chunk não pode cruzar fronteira de visibilidade num documento
-- misto, nem incluir página sem classificação explícita nesse caso — senão o chunk herdaria
-- (via pagina_ini) a visibilidade de UMA borda do intervalo, e o texto das demais páginas do
-- intervalo vazaria ou ficaria preso por engano. Só se aplica quando tem_paginas_mistas = true;
-- documento normal não paga este custo.
-- ============================================================================
create or replace function public.tg_chunks_valida_visibilidade_uniforme()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_misto        boolean;
  v_paginas      int;
  v_classificadas int;
  v_distintas    int;
begin
  select d.tem_paginas_mistas into v_misto
    from public.documentos d where d.id = new.documento_id;

  if coalesce(v_misto, false) then
    select
      count(*),
      count(*) filter (where dp.visibilidade is not null),
      count(distinct dp.visibilidade)
      into v_paginas, v_classificadas, v_distintas
      from public.documento_paginas dp
     where dp.documento_id = new.documento_id
       and dp.pagina between new.pagina_ini and new.pagina_fim;

    if v_paginas < (new.pagina_fim - new.pagina_ini + 1)
       or v_classificadas < v_paginas
       or v_distintas <> 1 then
      raise exception
        'Chunk (documento %, páginas %-%) cruza fronteira de visibilidade ou inclui página sem '
        'classificação explícita: documento marcado tem_paginas_mistas exige visibilidade '
        'uniforme e classificada em todo o intervalo do chunk (correção 2026-09-04, armadilha de '
        'conteúdo misto).', new.documento_id, new.pagina_ini, new.pagina_fim;
    end if;
  end if;

  return new;
end $$;

create trigger chunks_valida_visibilidade_uniforme
  before insert or update of documento_id, pagina_ini, pagina_fim on public.chunks
  for each row execute function public.tg_chunks_valida_visibilidade_uniforme();
