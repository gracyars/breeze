-- Breeze — baseline 12: seed de domínio — plano de contas.
-- Fonte: skill `condominio-plano-de-contas` §2 (receitas) e §3 (despesas). Idempotente via
-- staging + ON CONFLICT DO NOTHING (árvore com integridade estrutural via trigger
-- contas_valida_hierarquia — reaplicar com DO UPDATE arriscaria violar nivel/pai de dado real).
--
-- Este plano é o ESQUELETO DE PARTIDA (skill §8): cada condomínio real espelha 1:1 o plano da
-- administradora dele por cima deste. Nunca "corrigir" o nome dela.
--
-- Subgrupo 2.12 "Uso de fundos" (2.12.01/02) NÃO está na tabela da skill — é acréscimo do
-- eng-supabase, necessário para o alerta crítico "Fundo de reserva sem ata" (SPEC §5.3,
-- ADR-0016 item 6) ser avaliável: sem uma conta de DESPESA marcada fundo<>'nenhum' e
-- exige_deliberacao=true, nenhum lançamento poderia disparar a regra. As contas 1.3/1.4
-- (RECEITA, aporte ao fundo) já vinham da skill e não exigem ata — só a SAÍDA exige
-- (condominio-plano-de-contas §4).

create temporary table stg_contas (
  codigo             text primary key,
  nome               text not null,
  natureza           public.natureza_conta not null,
  fundo              public.fundo not null default 'nenhum',
  exige_deliberacao  boolean not null default false
) on commit drop;

insert into stg_contas (codigo, nome, natureza, fundo, exige_deliberacao) values
  -- ===== Grupo 1 — Receitas =====
  ('1',       'Receitas',                                                 'receita', 'nenhum',  false),
  ('1.1',     'Receitas ordinárias',                                      'receita', 'nenhum',  false),
  ('1.1.01',  'Taxa condominial ordinária',                                'receita', 'nenhum',  false),
  ('1.1.02',  'Taxa condominial — unidades não residenciais/comerciais',   'receita', 'nenhum',  false),
  ('1.2',     'Receitas extraordinárias',                                  'receita', 'nenhum',  false),
  ('1.2.01',  'Taxa extraordinária — rateio de obra específica',           'receita', 'nenhum',  false),
  ('1.2.02',  'Taxa extraordinária — reposição de fundo',                  'receita', 'nenhum',  false),
  ('1.3',     'Fundo de reserva',                                          'receita', 'reserva', false),
  ('1.3.01',  'Contribuição mensal ao fundo de reserva',                   'receita', 'reserva', false),
  ('1.3.02',  'Rendimento de aplicação do fundo de reserva',               'receita', 'reserva', false),
  ('1.4',     'Fundo de obras',                                            'receita', 'obras',   false),
  ('1.4.01',  'Contribuição mensal ao fundo de obras',                     'receita', 'obras',   false),
  ('1.4.02',  'Rendimento de aplicação do fundo de obras',                 'receita', 'obras',   false),
  ('1.5',     'Multas e juros',                                            'receita', 'nenhum',  false),
  ('1.5.01',  'Multa por atraso de taxa condominial',                      'receita', 'nenhum',  false),
  ('1.5.02',  'Juros de mora',                                             'receita', 'nenhum',  false),
  ('1.5.03',  'Multa por infração ao regimento interno',                   'receita', 'nenhum',  false),
  ('1.6',     'Rendimento de aplicação — conta corrente',                  'receita', 'nenhum',  false),
  ('1.6.01',  'Rendimento de conta corrente/poupança operacional',         'receita', 'nenhum',  false),
  ('1.7',     'Uso de área comum',                                         'receita', 'nenhum',  false),
  ('1.7.01',  'Locação de salão de festas',                                'receita', 'nenhum',  false),
  ('1.7.02',  'Locação de vaga de garagem',                                'receita', 'nenhum',  false),
  ('1.7.03',  'Locação de espaço para antena/publicidade/comércio',        'receita', 'nenhum',  false),
  ('1.8',     'Outras receitas',                                           'receita', 'nenhum',  false),
  ('1.8.01',  'Reembolso de sinistro (seguro)',                            'receita', 'nenhum',  false),
  ('1.8.02',  'Venda de material/sucata/bens inservíveis',                 'receita', 'nenhum',  false),
  ('1.8.03',  'Receitas diversas não classificadas',                       'receita', 'nenhum',  false),

  -- ===== Grupo 2 — Despesas =====
  ('2',       'Despesas',                                                  'despesa', 'nenhum',  false),
  ('2.1',     'Pessoal e encargos',                                        'despesa', 'nenhum',  false),
  ('2.1.01',  'Salários — equipe própria (zelador, porteiro, faxineira, jardineiro)', 'despesa', 'nenhum', false),
  ('2.1.02',  '13º salário',                                               'despesa', 'nenhum',  false),
  ('2.1.03',  'Férias e 1/3 constitucional',                               'despesa', 'nenhum',  false),
  ('2.1.04',  'FGTS',                                                      'despesa', 'nenhum',  false),
  ('2.1.05',  'INSS patronal',                                             'despesa', 'nenhum',  false),
  ('2.1.06',  'Rescisões e verbas trabalhistas',                           'despesa', 'nenhum',  false),
  ('2.1.07',  'Vale-transporte / vale-refeição / cesta básica',            'despesa', 'nenhum',  false),
  ('2.1.08',  'Exames ocupacionais (ASO) e medicina do trabalho',          'despesa', 'nenhum',  false),
  ('2.1.09',  'Uniformes e EPI',                                           'despesa', 'nenhum',  false),
  ('2.2',     'Administração',                                             'despesa', 'nenhum',  false),
  ('2.2.01',  'Taxa de administração (honorários da administradora)',      'despesa', 'nenhum',  false),
  ('2.2.02',  'Assessoria contábil',                                       'despesa', 'nenhum',  false),
  ('2.2.03',  'Assessoria jurídica preventiva/consultiva',                 'despesa', 'nenhum',  false),
  ('2.2.04',  'Material de escritório e expediente',                       'despesa', 'nenhum',  false),
  ('2.2.05',  'Correios, cartório e reconhecimento de firma',              'despesa', 'nenhum',  false),
  ('2.2.06',  'Tarifas e despesas bancárias',                              'despesa', 'nenhum',  false),
  ('2.2.07',  'Software/sistema de gestão condominial',                    'despesa', 'nenhum',  false),
  ('2.3',     'Manutenção predial',                                        'despesa', 'nenhum',  false),
  ('2.3.01',  'Manutenção hidráulica',                                     'despesa', 'nenhum',  false),
  ('2.3.02',  'Manutenção elétrica',                                       'despesa', 'nenhum',  false),
  ('2.3.03',  'Pintura e reparos gerais',                                  'despesa', 'nenhum',  false),
  ('2.3.04',  'Manutenção de esquadrias e portões',                        'despesa', 'nenhum',  false),
  ('2.3.05',  'Dedetização e controle de pragas',                          'despesa', 'nenhum',  false),
  ('2.3.06',  'Manutenção de bombas e pressurizadores',                    'despesa', 'nenhum',  false),
  ('2.3.07',  'Limpeza de caixa d''água/cisterna',                         'despesa', 'nenhum',  false),
  ('2.3.08',  'Jardinagem e paisagismo',                                   'despesa', 'nenhum',  false),
  ('2.3.09',  'Manutenção de piscina',                                     'despesa', 'nenhum',  false),
  ('2.4',     'Elevadores',                                                'despesa', 'nenhum',  false),
  ('2.4.01',  'Manutenção mensal (contrato fixo)',                         'despesa', 'nenhum',  false),
  ('2.4.02',  'Peças e reparos avulsos',                                   'despesa', 'nenhum',  false),
  ('2.4.03',  'Modernização/adequação normativa',                         'despesa', 'nenhum',  false),
  ('2.5',     'Limpeza e conservação',                                     'despesa', 'nenhum',  false),
  ('2.5.01',  'Material de limpeza',                                       'despesa', 'nenhum',  false),
  ('2.5.02',  'Serviço terceirizado de limpeza',                           'despesa', 'nenhum',  false),
  ('2.5.03',  'Coleta de lixo especial/reciclagem',                        'despesa', 'nenhum',  false),
  ('2.6',     'Segurança e portaria',                                      'despesa', 'nenhum',  false),
  ('2.6.01',  'Empresa de portaria/vigilância terceirizada',               'despesa', 'nenhum',  false),
  ('2.6.02',  'Monitoramento e manutenção de CFTV',                        'despesa', 'nenhum',  false),
  ('2.6.03',  'Manutenção de interfone/cerca elétrica/alarme',             'despesa', 'nenhum',  false),
  ('2.6.04',  'Central de monitoramento remoto',                           'despesa', 'nenhum',  false),
  ('2.7',     'Água, energia e gás',                                       'despesa', 'nenhum',  false),
  ('2.7.01',  'Água e esgoto — áreas comuns',                              'despesa', 'nenhum',  false),
  ('2.7.02',  'Energia elétrica — áreas comuns',                           'despesa', 'nenhum',  false),
  ('2.7.03',  'Gás (GLP/GN) — áreas comuns',                               'despesa', 'nenhum',  false),
  ('2.8',     'Seguros',                                                   'despesa', 'nenhum',  false),
  ('2.8.01',  'Seguro predial obrigatório (incêndio)',                     'despesa', 'nenhum',  false),
  ('2.8.02',  'Seguro de responsabilidade civil',                          'despesa', 'nenhum',  false),
  ('2.8.03',  'Seguro de vida da equipe',                                  'despesa', 'nenhum',  false),
  ('2.9',     'Jurídico',                                                  'despesa', 'nenhum',  false),
  ('2.9.01',  'Honorários advocatícios — ações judiciais',                 'despesa', 'nenhum',  false),
  ('2.9.02',  'Custas e despesas processuais',                             'despesa', 'nenhum',  false),
  ('2.9.03',  'Consultoria jurídica avulsa (fora do contrato de assessoria)', 'despesa', 'nenhum', false),
  ('2.10',    'Obras e melhorias',                                         'despesa', 'nenhum',  false),
  ('2.10.01', 'Obra de reforma estrutural',                                'despesa', 'nenhum',  false),
  ('2.10.02', 'Obra de acessibilidade',                                    'despesa', 'nenhum',  false),
  ('2.10.03', 'Modernização de fachada/áreas comuns',                      'despesa', 'nenhum',  false),
  ('2.10.04', 'Projetos técnicos e ART/RRT',                               'despesa', 'nenhum',  false),
  ('2.11',    'Taxas e tributos',                                          'despesa', 'nenhum',  false),
  ('2.11.01', 'Taxas municipais (alvará, licença de funcionamento)',       'despesa', 'nenhum',  false),
  ('2.11.02', 'IPTU de área comum, quando incidente',                      'despesa', 'nenhum',  false),
  ('2.11.03', 'Multas administrativas não trabalhistas',                   'despesa', 'nenhum',  false),
  ('2.12',    'Uso de fundos',                                             'despesa', 'nenhum',  false),
  ('2.12.01', 'Uso do fundo de reserva',                                   'despesa', 'reserva', true),
  ('2.12.02', 'Uso do fundo de obras',                                     'despesa', 'obras',   true);

-- Nível 1 — grupos.
insert into public.contas (codigo, nome, natureza, nivel, conta_pai_id, aceita_lancamento, fundo, exige_deliberacao)
select codigo, nome, natureza, 1, null, false, fundo, exige_deliberacao
  from stg_contas
 where codigo !~ '\.'
on conflict (codigo) do nothing;

-- Nível 2 — subgrupos.
insert into public.contas (codigo, nome, natureza, nivel, conta_pai_id, aceita_lancamento, fundo, exige_deliberacao)
select s.codigo, s.nome, s.natureza, 2, c1.id, false, s.fundo, s.exige_deliberacao
  from stg_contas s
  join public.contas c1 on c1.codigo = split_part(s.codigo, '.', 1) and c1.nivel = 1
 where s.codigo ~ '^[0-9]+\.[0-9]+$'
on conflict (codigo) do nothing;

-- Nível 3 — contas folha (só elas aceitam lançamento).
insert into public.contas (codigo, nome, natureza, nivel, conta_pai_id, aceita_lancamento, fundo, exige_deliberacao)
select s.codigo, s.nome, s.natureza, 3, c2.id, true, s.fundo, s.exige_deliberacao
  from stg_contas s
  join public.contas c2
    on c2.codigo = split_part(s.codigo, '.', 1) || '.' || split_part(s.codigo, '.', 2)
   and c2.nivel = 2
 where s.codigo ~ '^[0-9]+\.[0-9]+\.[0-9]+$'
on conflict (codigo) do nothing;
