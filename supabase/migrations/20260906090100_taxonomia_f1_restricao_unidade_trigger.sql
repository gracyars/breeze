-- Breeze — F1: trava de autorização — `demonstrativo_cota` e `comunicado` vinculados a uma
-- unidade específica (documento_unidades) NUNCA podem circular como `autenticado`.
--
-- Fonte: docs/dominio/taxonomia-documental-decisoes.md §5 e tabela de seed —
--   demonstrativo_cota: visibilidade_padrao autenticado, "⚠ restrito se unidade_id preenchida"
--   comunicado:         "unidade_destinataria nullable (preenchida → força restrito)"
-- — mesma régua já usada para notificação/multa e inadimplência (dado financeiro/pessoal
-- individualizado por unidade nunca fica exposto à base autenticada inteira).
--
-- POR QUE TRIGGER E NÃO SÓ CONVENÇÃO DE APLICAÇÃO: exatamente a armadilha nº1 do projeto
-- (SPEC §7) na sua forma "erro humano na hora de classificar", não na forma "predicado
-- copiado" — mas o dano é o mesmo: um demonstrativo de cota da unidade 302 publicado como
-- `autenticado` porque alguém esqueceu de trocar o campo expõe rateio nominal da 302 para
-- toda a base de moradores autenticados. CHECK não serve (precisa de subconsulta entre
-- `documentos` e `documento_unidades`) — mesmo motivo de tg_documentos_valida_visibilidade
-- (20260904120600).
--
-- DOIS LADOS (ADR-0021, "invariante de dois lados" — nenhuma invariante relacional se sustenta
-- validada só de um lado; ver também documento_paginas_valida_piso/documentos_valida_piso_paginas
-- em 20260904120800, mesmo padrão):
--   (a) tg_documento_unidades_exige_restrito — dispara ao criar/mudar o VÍNCULO
--       (documento_unidades). Se a visibilidade do documento ainda não é `restrito` no momento
--       do vínculo, rejeita.
--   (b) tg_documentos_bloqueia_rebaixar_restrito_vinculado — dispara ao mudar
--       `documentos.visibilidade`/`tipo`. Se já existe vínculo em documento_unidades e a nova
--       visibilidade deixaria de ser `restrito`, rejeita.
-- Sem os dois lados, a ordem de escrita decide se a trava funciona — a mesma classe de defeito
-- que o auditor-rls achou (V3-R) entre documento_paginas e documentos.
--
-- ESCOPO DELIBERADO: só `demonstrativo_cota` e `comunicado` — os dois tipos que a taxonomia
-- nova declara com vínculo de unidade OPCIONAL (visibilidade condicional ao conteúdo).
-- `notificacao_multa` tem o mesmo risco de fundo (visibilidade_padrao já é `restrito`, mas nada
-- no schema hoje impede alguém de rebaixar essa linha para `autenticado` com o vínculo já
-- criado) — gap PRÉ-EXISTENTE, fora do pedido desta rodada; não estendo a trava para lá sem
-- necessidade demonstrada (linha de escopo do orquestrador). Sinalizado no relatório para
-- `auditor-rls`/orquestrador decidirem se vale generalizar.

create or replace function public.tg_documento_unidades_exige_restrito()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_tipo         text;
  v_visibilidade public.visibilidade_documento;
begin
  select d.tipo, d.visibilidade into v_tipo, v_visibilidade
    from public.documentos d where d.id = new.documento_id;

  if v_tipo is null then
    raise exception 'documento_id % não existe em documentos', new.documento_id;
  end if;

  if v_tipo in ('demonstrativo_cota', 'comunicado') and v_visibilidade <> 'restrito' then
    raise exception
      'Documento % (tipo %) só pode ganhar vínculo em documento_unidades quando '
      'documentos.visibilidade = ''restrito'' — dado individualizado por unidade não pode '
      'circular como ''%''. Ajuste documentos.visibilidade antes de vincular a unidade '
      '(docs/dominio/taxonomia-documental-decisoes.md §5).',
      new.documento_id, v_tipo, v_visibilidade;
  end if;

  return new;
end $$;

create trigger documento_unidades_exige_restrito
  before insert or update of documento_id on public.documento_unidades
  for each row execute function public.tg_documento_unidades_exige_restrito();

create or replace function public.tg_documentos_bloqueia_rebaixar_restrito_vinculado()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.tipo in ('demonstrativo_cota', 'comunicado')
     and new.visibilidade <> 'restrito'
     and exists (select 1 from public.documento_unidades du where du.documento_id = new.id) then
    raise exception
      'Documento % (tipo %) está vinculado a uma unidade em documento_unidades — não pode '
      'deixar de ser ''restrito'' enquanto o vínculo existir (docs/dominio/'
      'taxonomia-documental-decisoes.md §5). Remova o vínculo antes de afrouxar a visibilidade.',
      new.id, new.tipo;
  end if;
  return new;
end $$;

create trigger documentos_bloqueia_rebaixar_restrito_vinculado
  before update of visibilidade, tipo on public.documentos
  for each row execute function public.tg_documentos_bloqueia_rebaixar_restrito_vinculado();

comment on function public.tg_documento_unidades_exige_restrito() is
  'Trava de autorização para demonstrativo_cota/comunicado individualizados por unidade — sem '
  'isto, visibilidade=autenticado com vínculo em documento_unidades expõe dado financeiro/'
  'pessoal nominal de uma unidade a toda a base autenticada. Testado em '
  'supabase/tests/06_taxonomia_f1_restricao_unidade.sql.';
comment on function public.tg_documentos_bloqueia_rebaixar_restrito_vinculado() is
  'Lado espelhado de tg_documento_unidades_exige_restrito (ADR-0021, invariante de dois lados) — '
  'impede rebaixar a visibilidade DEPOIS que o vínculo já existe.';

-- ============================================================================
-- Âncora de citação: deliberacoes.documento_id nunca aponta para resumo_assembleia.
-- Fonte: docs/dominio/taxonomia-documental-decisoes.md §3, item 3: "resumo NÃO é âncora
-- jurídica de deliberação" — resumo pode ser indexado/citado em busca livre (chunks/
-- documento_paginas continuam abertos a ele), mas nunca é o documento_id de uma linha em
-- `deliberacoes`. Regra de citação em `rag-citacao-juridica-ptbr` (Citacao.tipo, selo de
-- "Resumo da administração · não é a ata oficial") está fora do escopo de arquivo deste
-- agente — só a trava de dado é implementada aqui.
-- ============================================================================
create or replace function public.tg_deliberacoes_ancora_so_ata()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_tipo text;
begin
  if new.documento_id is null then
    return new;
  end if;

  select d.tipo into v_tipo from public.documentos d where d.id = new.documento_id;

  if v_tipo is null then
    raise exception 'documento_id % não existe em documentos', new.documento_id;
  end if;

  if v_tipo <> 'ata_assembleia' then
    raise exception
      'deliberacoes.documento_id (%) aponta para documento tipo ''%'' — só pode ancorar em '
      '''ata_assembleia''. Resumo de assembleia não é prova de deliberação (docs/dominio/'
      'taxonomia-documental-decisoes.md §3).', new.documento_id, v_tipo;
  end if;

  return new;
end $$;

create trigger deliberacoes_ancora_so_ata
  before insert or update of documento_id on public.deliberacoes
  for each row execute function public.tg_deliberacoes_ancora_so_ata();

comment on function public.tg_deliberacoes_ancora_so_ata() is
  'docs/dominio/taxonomia-documental-decisoes.md §3: resumo_assembleia nunca é âncora jurídica '
  'de deliberação — só ata_assembleia. Testado em '
  'supabase/tests/06_taxonomia_f1_restricao_unidade.sql.';
