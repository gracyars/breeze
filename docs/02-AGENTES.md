# Breeze — Roster de Agentes

Ainda **não criados**. Esta é a lista aprovada-para-criar, com modelo, gatilho e limite de escopo.

## Política de modelo

| Modelo | Quando | Por quê |
|---|---|---|
| **Opus** | Decisão difícil de reverter, dinheiro, segurança, arquitetura, revisão adversarial | Erro aqui custa mais que o token |
| **Sonnet** | Implementação com spec escrita, UI, refactor, testes | Volume do trabalho; qualidade suficiente quando a spec é boa |
| **Haiku** | Tarefa mecânica, repetitiva, verificação, extração estruturada em lote | Roda muitas vezes; custo domina |

**Regras de economia de token, obrigatórias para todo agente:**
1. Receber a spec por **caminho de arquivo**, nunca colada no prompt.
2. Devolver diff, decisão ou resumo — **nunca dump de arquivo**.
3. Um agente não relê o que outro já leu; o orquestrador carrega o contexto compartilhado.
4. Agente de implementação não faz pesquisa exploratória; se falta informação, pergunta ao orquestrador.
5. Escopo fechado por arquivo/diretório declarado — evita dois agentes escrevendo no mesmo lugar.

---

## Fundação e governança

| # | Agente | Modelo | Gatilho | Escopo |
|---|---|---|---|---|
| 1 | **arquiteto** | Opus | Início de fase, mudança estrutural, decisão de stack | ADRs, modelo de dados, migrações-mestre. Não escreve feature. |
| 2 | **guardiao-dominio** | Sonnet | Consultado por qualquer agente com dúvida de negócio | Plano de contas, taxonomia documental, papéis, regras condominiais. Fonte única de verdade de domínio. |
| 3 | **juridico-lgpd** | Opus | Antes de publicar qualquer coisa; ao mudar visibilidade ou retenção | Política de visibilidade, base legal, anonimização, prazos de guarda. Poder de veto. |

## Dados e busca

| # | Agente | Modelo | Gatilho | Escopo |
|---|---|---|---|---|
| 4 | **eng-ingestao** | Opus para desenhar / Sonnet para iterar | F1 | Pipeline PDF: extração, heurística de OCR, chunking page-aware, classificação, idempotência. |
| 5 | **eng-busca** | Opus | F1 | Config FTS PT-BR, pgvector, RRF, roteamento de intenção, prompt de síntese com citação. |
| 6 | **avaliador-busca** | Haiku | Toda alteração no ranking | Roda o conjunto de perguntas-gold, mede recall e precisão, reporta regressão. Barato e frequente. |
| 7 | **curador-acervo** | Haiku | Operacional contínuo | Confere extração, classifica documento, preenche metadados, sinaliza páginas de baixa confiança de OCR. |

## Backend

| # | Agente | Modelo | Gatilho | Escopo |
|---|---|---|---|---|
| 8 | **eng-supabase** | Sonnet | F0 e sob demanda | Schema, migrações versionadas, policies de RLS e de Storage, tipos gerados. |
| 9 | **auditor-rls** | Opus | Toda migração que toque policy | Testes pgTAP, tentativa **adversarial** de vazamento entre papéis. Bloqueia merge. |
| 10 | **eng-financeiro** | Sonnet | F2 e F3 | Importação assistida do balancete, travas de consistência, views orçado×realizado, motor de alertas. |
| 11 | **eng-auditoria** | Opus | F3 | Hash-chain do `audit.log`, imutabilidade, âncora semanal. Pequeno, crítico, faz uma coisa só. |

## Design e frontend

| # | Agente | Modelo | Gatilho | Escopo |
|---|---|---|---|---|
| 12 | **design-system** | Opus na direção inicial / Sonnet depois | F0, depois manutenção | Tokens, tipografia, paleta institucional, componentes shadcn, regras de gráfico. |
| 13 | **front-morador** | Sonnet | F1 | Busca, leitor de documento, biblioteca, início. A superfície que define o produto. |
| 14 | **front-gestao** | Sonnet | F2 e F3 | Conferência de balancete lado a lado, fila de alertas, questionamentos, parecer. |
| 15 | **acessibilidade** | Sonnet | Fim de cada fase | Auditoria WCAG, teclado, contraste, escala de fonte, teste com o cenário do usuário idoso. |
| 16 | **microcopy** | Haiku | Sob demanda | Textos de estado vazio, glossário contábil em linguagem simples, e-mail de convite, mensagens de erro sem jargão. |

## Qualidade e operação

| # | Agente | Modelo | Gatilho | Escopo |
|---|---|---|---|---|
| 17 | **qa-e2e** | Sonnet | Fim de fase e antes de deploy | Playwright nos fluxos críticos: buscar, abrir citação, conferir balancete, permissão por papel. |
| 18 | **revisor-critico** | Opus | PR em financeiro, auth, RLS ou ingestão | Code review adversarial. Não roda em PR de UI trivial — desperdício. |
| 19 | **devops** | Sonnet | F0 e antes de cada deploy | CI/CD, ambientes, migração, backup, runbook de restauração, teto de custo de LLM. |

---

## O que o orquestrador faz e não faz

Faz: sequenciar fases, escolher modelo, distribuir contexto, resolver conflito entre agentes,
levar decisão ao dono do projeto.
Não faz: escrever feature, revisar código linha a linha, pesquisar.

## Paralelização

- F0: `arquiteto` → depois `eng-supabase` ‖ `design-system` ‖ `devops`.
- F1: `eng-ingestao` ‖ `eng-busca` ‖ `front-morador` (contra dados de exemplo), converge no `avaliador-busca`.
- F2/F3: `eng-financeiro` ‖ `front-gestao`, com `juridico-lgpd` e `auditor-rls` como portões.
- Nunca dois agentes de implementação no mesmo diretório ao mesmo tempo.
