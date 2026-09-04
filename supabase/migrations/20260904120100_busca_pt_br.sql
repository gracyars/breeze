-- Breeze — baseline 01: configuração de busca textual PT-BR.
-- Precisa existir ANTES de qualquer coluna gerada que a use (chunks.tsv). Fonte: docs/schema.md §2,
-- ADR-0005.

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

comment on function public.unaccent_imutavel(text) is
  'Forma IMMUTABLE de unaccent, exigida por coluna gerada (ex.: sinonimos.termo_normalizado). '
  'unaccent(text) de 1 argumento é STABLE e não pode entrar em GENERATED ALWAYS AS.';

revoke all on function public.unaccent_imutavel(text) from public;
grant execute on function public.unaccent_imutavel(text) to anon, authenticated;
