# Breeze — Registro de Decisões

Decisões travadas. Um agente que discordar deve levantar com o orquestrador, não contornar.

## 2026-09-04

**D1 — Importação assistida do balancete: aprovada.** Extração propõe, humano confere lado a
lado com o PDF, travas de consistência contábil bloqueiam publicação divergente. Ver SPEC §5.1.

**D2 — Autenticação por CPF ou e-mail.** Sempre resolve em magic link no e-mail cadastrado.
CPF é alias, nunca credencial. Ver SPEC §2.1. *Consequência:* a decisão pendente sobre acervo
público perde urgência — se todo morador tem conta, o acervo fica atrás de login e a camada
pública se restringe a convenção e regimento.

**D3 — O síndico é terceirizado e não tem acesso ao sistema.** Ele é o fiscalizado, não um
usuário. *Consequências:* (a) o risco de conflito político com síndico-administrador some;
(b) o sistema é operado inteiramente pelo lado fiscalizador; (c) nenhum fluxo pode depender de
ação do síndico dentro do produto — o dado dele entra pelo PDF que ele envia.

**D4 — Papel `editor` único.** Só a dona do projeto escreve, por ora; a subsíndica entra depois,
sem prazo. *Consequências:* (a) o gargalo de publicação é humano e único — a curadoria do acervo
precisa ser rápida ou o produto morre de backlog; (b) o papel `conselho` ganha importância como
contrapeso, com leitura completa e independente; (c) a trilha de auditoria continua obrigatória,
agora para dar credibilidade à própria editora perante os moradores.

**D5 — Skills que tocam OCR fiscal, contabilidade condominial ou dado pessoal são escritas
internamente.** Marketplace comunitário serve para descobrir ideia, não para instalar.

**D6 — Skills de terceiros instaladas** (aprovadas em 2026-09-04): `playwright-best-practices`
(currents-dev), `vitest` (antfu), `a11y-playwright-testing` (fugazi), `postgres-hybrid-text-search`
(timescale, **como referência de RRF apenas** — pressupõe `pg_textsearch`, indisponível no
Supabase gerenciado). Recusadas: `pdf-extraction` (Python contra worker Node, sem OCR, autor com
nome que imita fonte oficial) e toda opção de pgTAP (nada maduro; a única candidata tinha 1
instalação e nenhum assessment de segurança). **pgTAP para testes de RLS será skill interna** —
adicionar ao backlog do `auditor-rls`.

**D7 — Achados jurídicos que contrariam o senso comum do domínio**, todos verificados em fonte
primária pela skill `condominio-legal`. Registrados porque material desatualizado circula muito
neste domínio e um agente pode "corrigir" o produto para o errado:
- Art. 1.351 mudou em 2022 (Lei 14.405): mudança de destinação do edifício **não exige mais
  unanimidade**, são 2/3.
- Lei 8.212/91 art. 32, §11 **não diz mais "dez anos"** desde 2009.
- Art. 1.337, parágrafo único (comportamento antissocial) **não tem quórum na lei**; os 3/4
  aplicados por analogia são doutrina — marcado `[QUÓRUM CONTROVERSO]`.
- Exigir contas é direito coletivo, não individual (STJ REsp 2.050.372). Ver SPEC §6.4-bis.
