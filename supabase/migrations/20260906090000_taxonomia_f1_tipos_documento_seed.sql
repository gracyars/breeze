-- Breeze — F1: taxonomia documental do acervo real — 5 tipos novos de `tipos_documento`.
-- Fonte: docs/dominio/taxonomia-documental-decisoes.md (guardiao-dominio, sonda de 43 PDFs
-- reais, docs/inventario-acervo.md), tabela "pronta para seed" no fim daquele documento.
--
-- Vai em MIGRAÇÃO, não em supabase/seed.sql — mesmo motivo de 20260904120700: é dado de
-- referência que precisa existir em TODO ambiente, inclusive produção. Idempotente via
-- ON CONFLICT — reaplicável sem duplicar.
--
-- O QUE NÃO ENTRA AQUI:
--   * `comunicado` NÃO muda de linha nesta migração. O "estreitamento de escopo" que o
--     guardiao-dominio decidiu (categoria financeiro|operacional|institucional;
--     unidade_destinataria nullable) é metadado POR DOCUMENTO — vive em
--     `documentos.metadados` (jsonb, já existente) e em `public.documento_unidades` (vínculo
--     já existente para visibilidade=restrito) — não em `tipos_documento`. A linha seedada em
--     20260904120700 (autenticado, 24 meses) permanece correta e intocada.
--   * `agi` como valor de `public.tipo_assembleia` NÃO entra aqui: já está em
--     `20260904120200_enums.sql` (CREATE TYPE original, não ALTER TYPE) — aplicado no
--     fechamento de F0 (commit c4d26bc), antes desta tarefa começar. Verificado, não
--     reintroduzido — ver relatório do eng-supabase para a evidência.
--
-- Regra de "dado individualizado por unidade" para `demonstrativo_cota` e `comunicado` (força
-- `restrito` quando vinculado a uma unidade específica) é IMPLEMENTADA por trigger, não por
-- valor de seed — ver 20260906090100_taxonomia_f1_restricao_unidade_trigger.sql. Aqui só o
-- catálogo; a trava de autorização é a migração seguinte.

insert into public.tipos_documento
  (codigo, nome, visibilidade_padrao, permite_publico, retencao_meses, ordem)
values
  -- Ordem escolhida para não renumerar as 14 linhas existentes (10..130) — só encaixa entre
  -- os vizinhos temáticos, sem exigir contiguidade (é só dica de ordenação de UI).
  ('resumo_assembleia',
   'Resumo de assembleia (não oficial)',                      'autenticado', false, null, 32),
  ('material_apoio_assembleia',
   'Material de apoio de assembleia',                          'autenticado', false, null, 34),
  ('comunicado_governanca',
   'Comunicado de governança (posse/renúncia/apresentação)',   'autenticado', false, null, 46),
  ('demonstrativo_cota',
   'Demonstrativo de composição de cota',                      'autenticado', false, null, 55),
  ('documento_construtora',
   'Documento da construtora / entrega de obra',                'autenticado', false, null, 125)
on conflict (codigo) do update set
  nome                = excluded.nome,
  visibilidade_padrao = excluded.visibilidade_padrao,
  permite_publico     = excluded.permite_publico,
  retencao_meses      = excluded.retencao_meses,
  ordem               = excluded.ordem;

comment on table public.tipos_documento is
  'RLS: leitura para todos (inclusive anon — a UI pública lista tipos); escrita só editor. '
  '19 tipos: 14 da baseline F0 + 5 do acervo real F1 (docs/dominio/taxonomia-documental-decisoes.md '
  '— resumo_assembleia, material_apoio_assembleia, comunicado_governanca, demonstrativo_cota, '
  'documento_construtora). Tabela de domínio: taxonomia cresce com a operação, sem exigir deploy '
  '(ADR-0015).';

comment on column public.tipos_documento.visibilidade_padrao is
  'Padrão do TIPO. `demonstrativo_cota` e `comunicado` nascem `autenticado` aqui, mas um '
  'DOCUMENTO individual desses tipos é forçado a `restrito` quando vinculado a uma unidade '
  'específica (documento_unidades) — trava em 20260906090100, não neste valor de seed (dado '
  'individualizado por unidade segue a régua de notificacao_multa/inadimplência).';
