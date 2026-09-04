-- Breeze — baseline 02: tipos enumerados (ADR-0015: enum para conjunto fechado, tabela de
-- domínio para conjunto operacional). Fonte: docs/schema.md §3, SPEC §2/§2.1.

-- Papel: TRÊS valores. sindico_terceirizado NÃO é papel de conta (D3, ADR-0016 item 4) —
-- existe como public.fornecedores.eh_sindico_terceirizado.
create type public.papel as enum ('editor', 'conselho', 'morador');

create type public.visibilidade_documento as enum (
  'publico',      -- só convenção e regimento (Briefing §7.1, SPEC §7)
  'autenticado',  -- qualquer morador logado
  'conselho',     -- conselho + editor
  'restrito'      -- conselho + editor + a unidade diretamente referida
);

create type public.status_documento as enum (
  'pendente',     -- linha criada, arquivo pode nem ter chegado
  'processando',  -- worker segurou o job
  'indexado',     -- texto extraído, chunks e embeddings prontos
  'em_revisao',   -- classificação proposta, aguardando confirmação humana (SPEC §3.5)
  'publicado',    -- visível conforme `visibilidade`
  'erro'
);
-- "Rascunho" não é status: é qualquer status <> 'publicado'. Nada chega ao morador sem
-- publicação explícita (SPEC §6.1) — a RLS do morador exige status = 'publicado'.

create type public.natureza_conta    as enum ('receita', 'despesa');
create type public.tipo_lancamento   as enum ('receita', 'despesa');
create type public.fundo             as enum ('nenhum', 'reserva', 'obras');
create type public.origem_lancamento as enum ('balancete_importado', 'manual', 'ajuste');
create type public.status_cobranca   as enum ('aberta', 'paga', 'atrasada', 'acordo', 'cancelada');
create type public.tipo_vinculo      as enum ('proprietario', 'inquilino', 'residente', 'procurador');
create type public.severidade_alerta as enum ('baixa', 'media', 'alta', 'critica');
create type public.status_alerta     as enum ('aberto', 'em_analise', 'resolvido', 'ignorado');
create type public.status_questionamento as enum ('aberto', 'respondido', 'resolvido');

-- 'agi' (Assembleia Geral de Instalação) acrescentado à luz da sonda real do acervo
-- (docs/inventario-acervo.md #2): a primeira ata do condomínio é uma AGI, 04.12.2025, ato
-- fundacional que a taxonomia original (só AGO/AGE) não cobria. Correção do orquestrador,
-- 2026-09-04.
create type public.tipo_assembleia as enum ('ago', 'age', 'agi', 'conselho_fiscal');

create type public.status_job as enum ('pendente', 'processando', 'concluido', 'erro', 'morto');
