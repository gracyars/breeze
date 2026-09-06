-- Breeze — F1 corte C6: `public.buscar_lexica` — a metade léxica da busca (ADR-0005, ADR-0027).
--
-- Por que existe uma função em vez de uma consulta pelo PostgREST: o resultado precisa vir
-- ordenado por `ts_rank_cd` e com o trecho literal marcado (`ts_headline`), e nenhuma das duas
-- coisas é expressável como filtro de PostgREST. Sem elas, a tela mostraria "achei 12 trechos" em
-- ordem arbitrária, sem dizer onde a palavra aparece — que é exatamente o que o SPEC §4 exige ao
-- contrário: o trecho original é o resultado PRIMÁRIO, não um detalhe.
--
-- `security invoker` — e isto é o ponto mais importante do arquivo: a função **não** tem
-- privilégio próprio. Ela lê `chunks` e `documentos` com a identidade de quem chamou, então a RLS
-- decide o que entra no resultado. Um chunk de página que a pessoa não enxerga não é filtrado
-- pela aplicação; ele não volta do banco. Se algum dia alguém marcar esta função como
-- `security definer` para "resolver" um resultado vazio, terá transformado a busca no maior
-- vazamento do produto.
-- Envelope para `websearch_to_tsquery` que devolve NULL em vez de estourar.
-- A consulta vem de caixa de texto de morador; `websearch_to_tsquery` aceita
-- quase tudo, mas expansão de sinônimo pode montar parêntese desbalanceado, e
-- erro de sintaxe de tsquery vira 500 no PostgREST — busca que quebra a tela em
-- vez de dizer "não achei".
create or replace function public.websearch_to_tsquery_pt(p_consulta text)
returns tsquery
language plpgsql
immutable
set search_path = ''
as $$
begin
  return websearch_to_tsquery('public.pt_br', coalesce(p_consulta, ''));
exception when others then
  return null;
end;
$$;

create or replace function public.buscar_lexica(
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
    -- O texto é escapado ANTES de virar HTML. `ts_headline` devolve marcação e
    -- não escapa nada do conteúdo: um PDF do acervo com `<script>` dentro (é
    -- documento de terceiro, não é nosso) viraria injeção na tela de quem busca.
    -- A ordem — escapar, depois marcar — é o que impede isso, e trocar a ordem
    -- reabre o buraco sem quebrar teste nenhum.
    ts_headline(
      'public.pt_br',
      replace(replace(c.texto, '&', '&amp;'), '<', '&lt;'),
      consulta.q,
      'StartSel=<mark>, StopSel=</mark>, MaxFragments=2, FragmentDelimiter=" … ", MaxWords=42, MinWords=18'
    ),
    -- Ordenação por FREQUÊNCIA (`ts_rank`), com densidade de cobertura
    -- (`ts_rank_cd`) só como desempate. Isto **diverge do ADR-0005**, que
    -- previa `ts_rank_cd` como a lista léxica, e a divergência foi medida no
    -- corpus real, não suposta: para "posso ter cachorro?" (a pergunta-exemplo
    -- do SPEC §6.2), `ts_rank_cd` põe o capítulo de OBRAS E REFORMAS acima do
    -- de ANIMAIS DOMÉSTICOS — 0,20 contra 0,01 — porque mede proximidade entre
    -- termos e é enganado por um chunk longo onde a expressão aparece uma vez,
    -- coladinha. `ts_rank` inverte corretamente (0,041 contra 0,019).
    -- Normalização 32 (`rank/(rank+1)`) mantém o valor entre 0 e 1, o que
    -- importa quando o RRF fundir esta lista com a semântica (ADR-0027).
    -- Proposta de emenda ao ADR-0005 registrada para o `arquiteto`.
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
revoke all on function public.websearch_to_tsquery_pt(text) from public;
-- `anon` também busca: a convenção e o regimento são públicos por decisão
-- (Briefing §7.1), e a RLS já limita o anônimo a documento publicado + público.
grant execute on function public.buscar_lexica(text, int) to anon, authenticated;
grant execute on function public.websearch_to_tsquery_pt(text) to anon, authenticated;

comment on function public.buscar_lexica(text, int) is
  'Metade léxica da busca (ADR-0005). SECURITY INVOKER de propósito: a RLS de chunks/documentos '
  'é quem filtra o resultado. NUNCA transformar em SECURITY DEFINER. O trecho vem de ts_headline '
  'sobre o texto JÁ ESCAPADO — a ordem escapar-depois-marcar é o que evita injeção a partir do '
  'conteúdo de um PDF de terceiro. A metade semântica (embedding + RRF) entra quando houver '
  'chave de LLM: ADR-0027.';
