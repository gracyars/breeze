-- Breeze — baseline 16: seed de domínio — tipos_alerta.
-- Fonte: SPEC §5.3 (as 10 regras do motor de alertas — o diferencial). Vai em MIGRAÇÃO pelo
-- mesmo motivo de tipos_documento: dado de referência necessário em todo ambiente, inclusive
-- produção.
--
-- requer_historico_meses: só variacao_atipica (média móvel de 6 meses) e fracionamento_suspeito
-- (base de comparação de 3 meses) dependem de série; as demais são avaliáveis desde o primeiro
-- balancete (ADR-0016 pendência b, D10). D10 (2026-09-04): o condomínio foi entregue em
-- dezembro/2025 — nove meses de operação até a data de hoje, então fracionamento_suspeito (3
-- meses) já é avaliável e variacao_atipica (6 meses) passa a valer agora TAMBÉM em teoria; mas o
-- acervo real hoje só tem 3 balancetes importados (dez/2025 a fev/2026,
-- docs/inventario-acervo.md) — é o motor de alertas (F3) que compara requer_historico_meses
-- contra a série REALMENTE disponível em `lancamentos`, não contra a data corrente. Ver
-- comentário em 20260904121800_sinonimos_configuracoes_seed.sql sobre por que
-- `competencia_mais_antiga` não é seedada como valor estático.

insert into public.tipos_alerta (codigo, nome, severidade_padrao, descricao_regra, requer_historico_meses)
values
  ('despesa_sem_comprovante',
   'Despesa sem comprovante',
   'alta',
   'Lançamento pago sem anexo em lancamento_anexos.',
   0),
  ('estouro_orcamento',
   'Estouro de orçamento',
   'media',
   'Conta atinge 80% do previsto (aviso) / >100% (crítico). Severidade efetiva varia por limiar '
   'em configuracoes (orcamento_aviso_pct / orcamento_critico_pct).',
   0),
  ('cotacao_ausente',
   'Cotação ausente',
   'alta',
   'Despesa não recorrente acima do limiar parametrizável (configuracoes.limiar_cotacao_centavos, '
   'sugestão inicial R$5.000) sem 2+ anexos tipo=cotacao.',
   0),
  ('fundo_sem_ata',
   'Fundo de reserva sem ata',
   'critica',
   'Débito em conta de fundo (contas.fundo <> ''nenhum'' e exige_deliberacao) sem '
   'deliberacao_id vinculada (ADR-0016 item 6).',
   0),
  ('contrato_vencendo',
   'Contrato vencendo',
   'media',
   '30 dias antes do fim da vigência (contratos.vigencia_fim), contrato não encerrado.',
   0),
  ('renovacao_nao_deliberada',
   'Renovação não deliberada',
   'alta',
   'Contrato acima da alçada renovado (contrato_anterior_id preenchido) sem deliberacao_id '
   'vinculada.',
   0),
  ('fornecedor_nao_cadastrado',
   'Fornecedor não cadastrado',
   'alta',
   'Pagamento a CNPJ/CPF ausente de fornecedores.',
   0),
  ('variacao_atipica',
   'Variação atípica',
   'media',
   'Conta varia >30% (configuracoes.variacao_atipica_pct) sobre a média móvel de 6 meses.',
   6),
  ('fracionamento_suspeito',
   'Fracionamento suspeito',
   'alta',
   'Múltiplos lançamentos, mesma conta e fornecedor, mesmo mês, somando acima do limiar de '
   'cotação — base de comparação de 3 meses.',
   3),
  ('troca_dados_bancarios',
   'Troca de dados bancários',
   'critica',
   'Alteração de conta em fornecedor_dados_bancarios de fornecedor recorrente (golpe do boleto).',
   0)
on conflict (codigo) do update set
  nome                    = excluded.nome,
  severidade_padrao       = excluded.severidade_padrao,
  descricao_regra         = excluded.descricao_regra,
  requer_historico_meses  = excluded.requer_historico_meses;
