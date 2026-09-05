-- Breeze — baseline 12: seed de domínio — plano de contas.
-- Fonte: skill `condominio-plano-de-contas` §2 (receitas) e §3 (despesas). Idempotente via
-- staging + ON CONFLICT DO NOTHING (árvore com integridade estrutural via trigger
-- contas_valida_hierarquia — reaplicar com DO UPDATE arriscaria violar nivel/pai de dado real).
--
-- Este plano é o ESQUELETO DE PARTIDA (skill §8): cada condomínio real espelha 1:1 o plano da
-- administradora dele por cima deste. Nunca "corrigir" o nome dela.
--
-- [D12, docs/dominio/plano-de-contas-decisoes.md] O subgrupo 2.12 "Uso de fundos" (2.12.01/02),
-- que uma versão anterior desta migração acrescentava, foi REMOVIDO: "uso de fundo" não é
-- despesa autônoma, é a MESMA despesa finalística (bomba, obra, elevador) paga com recurso de
-- origem diferente. Empilhar isso numa conta própria mistura naturezas incompatíveis e diverge
-- do balancete real da administradora (skill §8). A origem do recurso é atributo do LANÇAMENTO
-- (`lancamentos.fundo`), nunca da conta — avaliável independente de qual conta foi debitada. O
-- alerta "fundo de reserva sem ata" (SPEC §5.3) passou a usar
-- `lancamentos.fundo <> 'nenhum' AND deliberacao_id IS NULL` (índice `lancamentos_fundo_idx` já
-- existente) em vez de uma flag fixa na conta — ver 20260904121300_lancamentos.sql.

create temporary table stg_contas (
  codigo             text primary key,
  nome               text not null,
  natureza           public.natureza_conta not null,
  fundo              public.fundo not null default 'nenhum'
) on commit drop;

insert into stg_contas (codigo, nome, natureza, fundo) values
  -- ===== Grupo 1 — Receitas =====
  ('1',       'Receitas',                                                 'receita', 'nenhum'),
  ('1.1',     'Receitas ordinárias',                                      'receita', 'nenhum'),
  ('1.1.01',  'Taxa condominial ordinária',                                'receita', 'nenhum'),
  ('1.1.02',  'Taxa condominial — unidades não residenciais/comerciais',   'receita', 'nenhum'),
  ('1.2',     'Receitas extraordinárias',                                  'receita', 'nenhum'),
  ('1.2.01',  'Taxa extraordinária — rateio de obra específica',           'receita', 'nenhum'),
  ('1.2.02',  'Taxa extraordinária — reposição de fundo',                  'receita', 'nenhum'),
  ('1.3',     'Fundo de reserva',                                          'receita', 'reserva'),
  ('1.3.01',  'Contribuição mensal ao fundo de reserva',                   'receita', 'reserva'),
  ('1.3.02',  'Rendimento de aplicação do fundo de reserva',               'receita', 'reserva'),
  ('1.4',     'Fundo de obras',                                            'receita', 'obras'),
  ('1.4.01',  'Contribuição mensal ao fundo de obras',                     'receita', 'obras'),
  ('1.4.02',  'Rendimento de aplicação do fundo de obras',                 'receita', 'obras'),
  ('1.5',     'Multas e juros',                                            'receita', 'nenhum'),
  ('1.5.01',  'Multa por atraso de taxa condominial',                      'receita', 'nenhum'),
  ('1.5.02',  'Juros de mora',                                             'receita', 'nenhum'),
  ('1.5.03',  'Multa por infração ao regimento interno',                   'receita', 'nenhum'),
  ('1.6',     'Rendimento de aplicação — conta corrente',                  'receita', 'nenhum'),
  ('1.6.01',  'Rendimento de conta corrente/poupança operacional',         'receita', 'nenhum'),
  ('1.7',     'Uso de área comum',                                         'receita', 'nenhum'),
  ('1.7.01',  'Locação de salão de festas',                                'receita', 'nenhum'),
  ('1.7.02',  'Locação de vaga de garagem',                                'receita', 'nenhum'),
  ('1.7.03',  'Locação de espaço para antena/publicidade/comércio',        'receita', 'nenhum'),
  ('1.8',     'Outras receitas',                                           'receita', 'nenhum'),
  ('1.8.01',  'Reembolso de sinistro (seguro)',                            'receita', 'nenhum'),
  ('1.8.02',  'Venda de material/sucata/bens inservíveis',                 'receita', 'nenhum'),
  ('1.8.03',  'Receitas diversas não classificadas',                       'receita', 'nenhum'),

  -- ===== Grupo 2 — Despesas =====
  ('2',       'Despesas',                                                  'despesa', 'nenhum'),
  ('2.1',     'Pessoal e encargos',                                        'despesa', 'nenhum'),
  ('2.1.01',  'Salários — equipe própria (zelador, porteiro, faxineira, jardineiro)', 'despesa', 'nenhum'),
  ('2.1.02',  '13º salário',                                               'despesa', 'nenhum'),
  ('2.1.03',  'Férias e 1/3 constitucional',                               'despesa', 'nenhum'),
  ('2.1.04',  'FGTS',                                                      'despesa', 'nenhum'),
  ('2.1.05',  'INSS patronal',                                             'despesa', 'nenhum'),
  ('2.1.06',  'Rescisões e verbas trabalhistas',                           'despesa', 'nenhum'),
  ('2.1.07',  'Vale-transporte / vale-refeição / cesta básica',            'despesa', 'nenhum'),
  ('2.1.08',  'Exames ocupacionais (ASO) e medicina do trabalho',          'despesa', 'nenhum'),
  ('2.1.09',  'Uniformes e EPI',                                           'despesa', 'nenhum'),
  ('2.2',     'Administração',                                             'despesa', 'nenhum'),
  ('2.2.01',  'Taxa de administração (honorários da administradora)',      'despesa', 'nenhum'),
  ('2.2.02',  'Assessoria contábil',                                       'despesa', 'nenhum'),
  ('2.2.03',  'Assessoria jurídica preventiva/consultiva',                 'despesa', 'nenhum'),
  ('2.2.04',  'Material de escritório e expediente',                       'despesa', 'nenhum'),
  ('2.2.05',  'Correios, cartório e reconhecimento de firma',              'despesa', 'nenhum'),
  ('2.2.06',  'Tarifas e despesas bancárias',                              'despesa', 'nenhum'),
  ('2.2.07',  'Software/sistema de gestão condominial',                    'despesa', 'nenhum'),
  ('2.3',     'Manutenção predial',                                        'despesa', 'nenhum'),
  ('2.3.01',  'Manutenção hidráulica',                                     'despesa', 'nenhum'),
  ('2.3.02',  'Manutenção elétrica',                                       'despesa', 'nenhum'),
  ('2.3.03',  'Pintura e reparos gerais',                                  'despesa', 'nenhum'),
  ('2.3.04',  'Manutenção de esquadrias e portões',                        'despesa', 'nenhum'),
  ('2.3.05',  'Dedetização e controle de pragas',                          'despesa', 'nenhum'),
  ('2.3.06',  'Manutenção de bombas e pressurizadores',                    'despesa', 'nenhum'),
  ('2.3.07',  'Limpeza de caixa d''água/cisterna',                         'despesa', 'nenhum'),
  ('2.3.08',  'Jardinagem e paisagismo',                                   'despesa', 'nenhum'),
  ('2.3.09',  'Manutenção de piscina',                                     'despesa', 'nenhum'),
  ('2.4',     'Elevadores',                                                'despesa', 'nenhum'),
  ('2.4.01',  'Manutenção mensal (contrato fixo)',                         'despesa', 'nenhum'),
  ('2.4.02',  'Peças e reparos avulsos',                                   'despesa', 'nenhum'),
  ('2.4.03',  'Modernização/adequação normativa',                         'despesa', 'nenhum'),
  ('2.5',     'Limpeza e conservação',                                     'despesa', 'nenhum'),
  ('2.5.01',  'Material de limpeza',                                       'despesa', 'nenhum'),
  ('2.5.02',  'Serviço terceirizado de limpeza',                           'despesa', 'nenhum'),
  ('2.5.03',  'Coleta de lixo especial/reciclagem',                        'despesa', 'nenhum'),
  ('2.6',     'Segurança e portaria',                                      'despesa', 'nenhum'),
  ('2.6.01',  'Empresa de portaria/vigilância terceirizada',               'despesa', 'nenhum'),
  ('2.6.02',  'Monitoramento e manutenção de CFTV',                        'despesa', 'nenhum'),
  ('2.6.03',  'Manutenção de interfone/cerca elétrica/alarme',             'despesa', 'nenhum'),
  ('2.6.04',  'Central de monitoramento remoto',                           'despesa', 'nenhum'),
  ('2.7',     'Água, energia e gás',                                       'despesa', 'nenhum'),
  ('2.7.01',  'Água e esgoto — áreas comuns',                              'despesa', 'nenhum'),
  ('2.7.02',  'Energia elétrica — áreas comuns',                           'despesa', 'nenhum'),
  ('2.7.03',  'Gás (GLP/GN) — áreas comuns',                               'despesa', 'nenhum'),
  ('2.8',     'Seguros',                                                   'despesa', 'nenhum'),
  ('2.8.01',  'Seguro predial obrigatório (incêndio)',                     'despesa', 'nenhum'),
  ('2.8.02',  'Seguro de responsabilidade civil',                          'despesa', 'nenhum'),
  ('2.8.03',  'Seguro de vida da equipe',                                  'despesa', 'nenhum'),
  ('2.9',     'Jurídico',                                                  'despesa', 'nenhum'),
  ('2.9.01',  'Honorários advocatícios — ações judiciais',                 'despesa', 'nenhum'),
  ('2.9.02',  'Custas e despesas processuais',                             'despesa', 'nenhum'),
  ('2.9.03',  'Consultoria jurídica avulsa (fora do contrato de assessoria)', 'despesa', 'nenhum'),
  ('2.10',    'Obras e melhorias',                                         'despesa', 'nenhum'),
  ('2.10.01', 'Obra de reforma estrutural',                                'despesa', 'nenhum'),
  ('2.10.02', 'Obra de acessibilidade',                                    'despesa', 'nenhum'),
  ('2.10.03', 'Modernização de fachada/áreas comuns',                      'despesa', 'nenhum'),
  ('2.10.04', 'Projetos técnicos e ART/RRT',                               'despesa', 'nenhum'),
  ('2.11',    'Taxas e tributos',                                          'despesa', 'nenhum'),
  ('2.11.01', 'Taxas municipais (alvará, licença de funcionamento)',       'despesa', 'nenhum'),
  ('2.11.02', 'IPTU de área comum, quando incidente',                      'despesa', 'nenhum'),
  ('2.11.03', 'Multas administrativas não trabalhistas',                   'despesa', 'nenhum');

-- Nível 1 — grupos.
insert into public.contas (codigo, nome, natureza, nivel, conta_pai_id, aceita_lancamento, fundo)
select codigo, nome, natureza, 1, null, false, fundo
  from stg_contas
 where codigo !~ '\.'
on conflict (codigo) do nothing;

-- Nível 2 — subgrupos.
insert into public.contas (codigo, nome, natureza, nivel, conta_pai_id, aceita_lancamento, fundo)
select s.codigo, s.nome, s.natureza, 2, c1.id, false, s.fundo
  from stg_contas s
  join public.contas c1 on c1.codigo = split_part(s.codigo, '.', 1) and c1.nivel = 1
 where s.codigo ~ '^[0-9]+\.[0-9]+$'
on conflict (codigo) do nothing;

-- Nível 3 — contas folha (só elas aceitam lançamento).
insert into public.contas (codigo, nome, natureza, nivel, conta_pai_id, aceita_lancamento, fundo)
select s.codigo, s.nome, s.natureza, 3, c2.id, true, s.fundo
  from stg_contas s
  join public.contas c2
    on c2.codigo = split_part(s.codigo, '.', 1) || '.' || split_part(s.codigo, '.', 2)
   and c2.nivel = 2
 where s.codigo ~ '^[0-9]+\.[0-9]+\.[0-9]+$'
on conflict (codigo) do nothing;
