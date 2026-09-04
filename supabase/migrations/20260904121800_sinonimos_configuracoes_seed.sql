-- Breeze — baseline 18: seed de domínio — sinonimos e configuracoes.
-- Fonte: SPEC §4 (sinônimos), SPEC §5.3 (limiares), skill `condominio-plano-de-contas` §6,
-- docs/04-DECISOES.md D10 (data de entrega do condomínio).

-- ============================================================================
-- sinonimos — SPEC §4 (seed mínimo obrigatório) + skill condominio-plano-de-contas §6
-- ============================================================================
insert into public.sinonimos (termo, expansoes) values
  ('taxa condominial',    array['cota', 'rateio']),
  ('fundo de reserva',    array['FR', 'reserva técnica']),
  ('prestação de contas', array['balancete']),
  ('AGE',                 array['assembleia extraordinária']),
  -- Adicionais da skill condominio-plano-de-contas §6 (vocabulário de administradora):
  ('taxa de administração', array['taxa de adm', 'honorários administração', 'adm. condominial', 'taxa administrativa', 'gestão condominial']),
  ('salários',               array['folha de pagamento', 'salários e ordenados', 'mão de obra própria']),
  ('portaria',               array['vigilância', 'segurança patrimonial', 'portaria terceirizada'])
on conflict (termo_normalizado) do nothing;

-- ============================================================================
-- configuracoes — limiares vivem em tabela, nunca em código (SPEC §5.3). Todos publica=false
-- (gestão-only) exceto condominio_data_instalacao, que só informa "há quanto tempo o condomínio
-- existe" para a UI mostrar "aguardando histórico" — não é limiar de fiscalização, não é convite
-- a burlar regra (SPEC §5.3: "saber que a cotação só é exigida acima de R$5.000 é convite a
-- fracionar em R$4.999" NÃO se aplica a uma data de entrega).
-- ============================================================================
insert into public.configuracoes (chave, valor, descricao, publica) values
  ('limiar_cotacao_centavos', '500000'::jsonb,
   'Despesa não recorrente acima deste valor exige 2+ cotações anexadas (SPEC §5.3). Sugestão inicial R$5.000.',
   false),
  ('orcamento_aviso_pct', '80'::jsonb,
   'Conta atinge este % do previsto no orçamento -> alerta severidade média (SPEC §5.3).',
   false),
  ('orcamento_critico_pct', '100'::jsonb,
   'Conta ultrapassa este % do previsto no orçamento -> alerta severidade alta (SPEC §5.3).',
   false),
  ('variacao_atipica_pct', '30'::jsonb,
   'Conta varia mais que este % sobre a média móvel de 6 meses -> alerta "variação atípica" (SPEC §5.3).',
   false),
  ('ocr_min_chars_pagina', '100'::jsonb,
   'Abaixo deste nº de caracteres extraídos, a página é candidata a OCR (ADR-0006/skill ocr-documento-fiscal-br).',
   false),
  ('ocr_max_gibberish_ratio', '0.30'::jsonb,
   'Acima desta razão de caracteres não-alfanuméricos/ruído, o texto extraído é tratado como degradado e a página exige revisão humana. [Decisão de produto — ajustável sem migração.]',
   false),
  ('contrato_aviso_dias', '30'::jsonb,
   'Dias antes do fim da vigência para disparar o alerta "contrato vencendo" (SPEC §5.3).',
   false),
  ('rrf_k', '60'::jsonb,
   'Constante k do Reciprocal Rank Fusion na busca híbrida (skill postgres-hybrid-text-search, ADR-0005).',
   false),
  ('busca_top_k', '50'::jsonb,
   'Nº de candidatos por ramo (lexical/vetorial) antes da fusão RRF.',
   false),
  ('condominio_data_instalacao', '"2025-12-01"'::jsonb,
   'Data da AGI (Assembleia Geral de Instalação), 04.12.2025 — confirmada em D10/docs/04-DECISOES.md '
   'e docs/inventario-acervo.md. Usada para a UI mostrar "aguardando histórico" quando '
   'tipos_alerta.requer_historico_meses ainda não é alcançável.',
   true)
on conflict (chave) do update set
  valor       = excluded.valor,
  descricao   = excluded.descricao,
  publica     = excluded.publica;

-- `competencia_mais_antiga` (ADR-0016 pendência b) DELIBERADAMENTE NÃO é seedada aqui como valor
-- estático: schema.md a descreve como "derivada de lancamentos" — precisa refletir
-- MIN(lancamentos.data_competencia) real, e um valor fixo ficaria errado assim que o primeiro
-- balancete de fato for importado (hoje o acervo real tem só 3 competências, dez/2025 a fev/2026
-- — docs/inventario-acervo.md; D10). Fica para o motor de alertas (F3) calcular em tempo de
-- avaliação, não para a baseline fixar um número que vai ficar obsoleto no primeiro import.
