-- Breeze — F1 corte C8: `buscar_lexica` passa a devolver também o texto do chunk.
--
-- Motivo, e ele é o do ADR-0028: a ata da AGE de 04.02.2026 embute o Regimento
-- Interno inteiro como anexo, então buscar "animais domésticos" devolve a mesma
-- regra duas vezes — uma no Regimento, outra dentro da ata. Medido no acervo
-- carregado: os quatro primeiros resultados dessa busca são dois pares.
--
-- A deduplicação compara conteúdo, e para isso precisa do **texto do chunk**, não
-- do realce: `ts_headline` devolve fragmento, com `…` no meio e marcação HTML no
-- lugar dos termos casados — comparar dois fragmentos mediria a consulta, não o
-- documento.
--
-- A deduplicação em si fica na **aplicação** (`lib/busca/deduplica.ts`), depois da
-- RLS. É ranking, não autorização: fundir dentro de uma policy seria decidir
-- sobre uma linha lendo outras, que é a não-localidade que o ADR-0023 proibiu
-- depois de ela ter vazado uma vez.
--
-- `returns table` não pode ser alterado por `create or replace` — daí o drop.
drop function if exists public.buscar_lexica(text, int);

create function public.buscar_lexica(
  p_consulta text,
  p_limite   int default 10
)
returns table (
  chunk_id     uuid,
  documento_id uuid,
  titulo       text,
  tipo         text,
  pagina_ini   int,
  pagina_fim   int,
  secao        text,
  trecho       text,
  texto        text,
  rank         real
)
language sql
stable
security invoker
set search_path = ''
as $$
  with consulta as (
    select public.websearch_to_tsquery_pt(p_consulta) as q
  )
  select
    c.id,
    c.documento_id,
    d.titulo,
    d.tipo,
    c.pagina_ini,
    c.pagina_fim,
    c.secao,
    -- Escapar ANTES de marcar: `ts_headline` devolve marcação e não escapa o
    -- conteúdo. O acervo é PDF de terceiro; um `<script>` lá dentro viraria
    -- injeção na tela de quem busca. Trocar a ordem reabre o buraco sem quebrar
    -- teste nenhum.
    ts_headline(
      'public.pt_br',
      replace(replace(c.texto, '&', '&amp;'), '<', '&lt;'),
      consulta.q,
      'StartSel=<mark>, StopSel=</mark>, MaxFragments=2, FragmentDelimiter=" … ", MaxWords=42, MinWords=18'
    ),
    -- Texto cru, para a deduplicação por conteúdo. Não vai para a tela: o que a
    -- tela mostra é o `trecho`.
    c.texto,
    -- `ts_rank` (frequência) e não `ts_rank_cd` (densidade de cobertura), com
    -- `ts_rank_cd` só como desempate. Divergência do ADR-0005 medida no corpus
    -- real: para "posso ter cachorro?", a densidade põe OBRAS E REFORMAS acima de
    -- ANIMAIS DOMÉSTICOS (0,20 contra 0,01), enganada por um trecho longo onde a
    -- expressão aparece uma vez, coladinha.
    ts_rank(c.tsv, consulta.q, 32)
  from public.chunks c
  join public.documentos d on d.id = c.documento_id
  cross join consulta
  where consulta.q is not null
    and c.tsv @@ consulta.q
  order by ts_rank(c.tsv, consulta.q, 32) desc,
           ts_rank_cd(c.tsv, consulta.q) desc,
           c.documento_id, c.ordem
  limit greatest(1, least(coalesce(p_limite, 10), 50));
$$;

revoke all on function public.buscar_lexica(text, int) from public;
grant execute on function public.buscar_lexica(text, int) to anon, authenticated;

comment on function public.buscar_lexica(text, int) is
  'Metade léxica da busca (ADR-0005). SECURITY INVOKER de propósito: a RLS de chunks/documentos '
  'é quem filtra o resultado. NUNCA transformar em SECURITY DEFINER. Devolve `trecho` (realce '
  'para a tela, com o texto escapado ANTES de marcado) e `texto` (cru, para a deduplicação por '
  'conteúdo do ADR-0028, feita na aplicação depois da RLS). A metade semântica entra quando '
  'houver chave de LLM: ADR-0027.';
