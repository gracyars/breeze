-- Breeze — baseline 07: seed de domínio — tipos_documento.
-- Fonte: skill `condominio-documentos`; docs/schema.md §6.1; SPEC §2.
--
-- Vai em MIGRAÇÃO, não em supabase/seed.sql: é dado de referência que precisa existir em TODO
-- ambiente, inclusive produção (seed.sql só roda em `db reset` local/CI, nunca em `db push`
-- remoto). Idempotente via ON CONFLICT — reaplicável sem duplicar.
--
-- 'comunicado' acrescentado à luz da sonda do acervo real (docs/inventario-acervo.md): 24 dos 43
-- documentos (56%) são avisos avulsos de gestão sem tipo formal na taxonomia original — achado
-- estrutural, não ruído. Autenticado/não-público por padrão (carrega nome, unidade, valor
-- individual conforme o caso — mesma régua de balancete/ata). Retenção de 24 meses é decisão de
-- produto, não obrigação legal identificada — mesma régua de apolice_seguro/notificacao_multa
-- (schema.md §6.1: "retenção informa obrigação mínima de guarda, nunca gatilho de expurgo").

insert into public.tipos_documento
  (codigo, nome, visibilidade_padrao, permite_publico, retencao_meses, ordem)
values
  ('convencao',            'Convenção de condomínio',              'publico',     true,  null, 10),
  ('regimento',             'Regimento interno',                    'publico',     true,  null, 20),
  ('ata_assembleia',        'Ata de assembleia (AGO/AGE/AGI)',       'autenticado', false, null, 30),
  ('edital_convocacao',     'Edital de convocação',                 'autenticado', false, 60,   40),
  ('comunicado',            'Comunicado avulso',                    'autenticado', false, 24,   45),
  ('balancete',             'Balancete mensal',                     'autenticado', false, null, 50),
  ('prestacao_contas',      'Prestação de contas anual',            'autenticado', false, null, 60),
  ('previsao_orcamentaria', 'Previsão orçamentária',                'autenticado', false, null, 70),
  ('contrato',              'Contrato de fornecedor',               'autenticado', false, null, 80),
  ('apolice_seguro',        'Apólice de seguro',                    'autenticado', false, 60,   90),
  ('laudo_tecnico',         'Laudo técnico (AVCB, SPDA, elevador…)', 'autenticado', false, null, 100),
  ('notificacao_multa',     'Notificação / multa',                  'restrito',    false, 60,   110),
  ('documentacao_obra',     'Documentação de obra',                 'autenticado', false, null, 120),
  ('ata_conselho',          'Ata do conselho fiscal',                'conselho',    false, null, 130)
on conflict (codigo) do update set
  nome                = excluded.nome,
  visibilidade_padrao = excluded.visibilidade_padrao,
  permite_publico     = excluded.permite_publico,
  retencao_meses      = excluded.retencao_meses,
  ordem               = excluded.ordem;

comment on table public.tipos_documento is
  'RLS: leitura para todos (inclusive anon — a UI pública lista tipos); escrita só editor. '
  'Seed inicial: 14 tipos (13 da skill condominio-documentos + comunicado, achado estrutural da '
  'sonda de acervo real de 2026-09-04 — docs/inventario-acervo.md). Tabela de domínio: taxonomia '
  'cresce com a operação, sem exigir deploy (ADR-0015).';
