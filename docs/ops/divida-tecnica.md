# Dívida técnica rastreada — F0

Fonte: `docs/auditoria/veredito-f0.md` (auditoria de RLS, 4 rodadas, aprovada em 2026-09-04,
176/176 asserts). Este documento existe para que os itens que o veredito listou como "fora de
cobertura" ou "observação com dono" não evaporem depois que F0 fechar — cada linha tem dono e
fica aberta até quem é dono marcar como resolvida (com data e como resolveu, não só riscar).

Regra de manutenção: quem resolve um item edita a linha (status, data, referência ao commit/PR
que resolveu) — não apaga a linha. Item sem dono não entra nesta tabela; volta para o
orquestrador decidir quem assume.

---

## Itens do `devops`

| # | Item | Risco se não resolvido | Status |
|---|---|---|---|
| D1 | **Emissão real de `aal2` pelo GoTrue não validada.** A suíte pgTAP simula o claim `aal` diretamente no JWT de teste — nunca exercitou o fluxo real de enrollment + verificação de TOTP do Supabase Auth para confirmar que o GoTrue só emite `aal2` depois do segundo fator de verdade (e não, por exemplo, logo após o enrollment, antes da primeira verificação). Se o GoTrue emitir `aal2` cedo demais, toda a autorização de `editor`/`conselho` (ADR-0003/0012, que depende de `aal2` no JWT) fica mais fraca do que a suíte local mede. | **Alto.** É a base de toda a autorização de papel privilegiado; um erro aqui não aparece em nenhum teste atual. | **Aberto.** Nenhuma verificação feita ainda contra um projeto Supabase real (local ou hospedado) exercitando o fluxo de MFA ponta a ponta pelo SDK/API, só leitura de comportamento esperado. |
| D2 | **Comportamento em Supabase hospedado não confirmado.** Toda a suíte (176 asserts) rodou contra o stack local (`supabase start`, Postgres em container Docker). O bloqueio de `TRUNCATE` para `service_role` foi confirmado como propriedade do Postgres em si (grants), então vale nos dois ambientes. O resto — timing de `aal2` (D1), comportamento de `pg_net`/extensões geridas, papéis/roles internos do Supabase hospedado — não foi exercitado contra um projeto real. | **Médio-alto.** Diferença de ambiente hospedado é justamente o tipo de coisa que só aparece em produção se não for testada antes. | **Aberto.** Bloqueado por decisão pendente de provisionar um projeto Supabase remoto de staging (fora do escopo/orçamento deste agente decidir sozinho — ver `docs/ops/backup.md` §3 e `.claude/agents/devops.md`, "Quando escalar": mudança/provisionamento de provedor é decisão conjunta `arquiteto` + dona do projeto). |
| D3 | **`pg_prove` — mecanismo de execução no CI, não só localmente.** Nesta rodada de fechamento: `pg_prove` foi instalado nesta máquina (`cpanm TAP::Parser::SourceHandler::pgTAP`) e `.github/workflows/ci.yml` (job `rls-test`) passou a instalá-lo de verdade no runner (apt `libtap-parser-sourcehandler-pgtap-perl`, com fallback `cpanm`) em vez de depender do fallback interno do Supabase CLI. Rodei a suíte real 3 vezes nesta máquina (2 sobre o mesmo stack, 1 após `supabase db reset --local` completo) — **176/176, determinístico, exit code 0** nas três, igual ao veredito do `auditor-rls`. | **Baixo, residual.** A mecânica de execução local está confirmada; o que não foi confirmado é o runner real do GitHub Actions (imagem `ubuntu-latest` hospedada), só simulado aqui via Docker Desktop no macOS. | **Mitigado nesta rodada, não fechado.** Fecha de verdade na primeira execução real do workflow num runner do GitHub — pendente até o repositório ter remoto (ver pendência de provisionamento em relatórios anteriores deste agente). |

---

## Itens do `eng-supabase`

| # | Item | Risco se não resolvido | Status |
|---|---|---|---|
| E1 | **Storage API real não coberta pela suíte.** A suíte pgTAP testou a RLS de `storage.objects`; signed URL, TTL curto (60–300s, SPEC §7) e a checagem de papel no servidor que emite a URL são código de aplicação, fora do alcance de pgTAP. | **Alto** — é exatamente o mecanismo que protege anexo financeiro (SPEC §7, "nunca embutida em página cacheada na CDN"). | Aberto — dívida de F1 (upload/leitura de documento). |
| E2 | **Documento pode sumir da busca em silêncio.** O invalidador de chunks aposta em reprocessamento idempotente do worker, mas nada no schema enfileira esse reprocessamento — nenhuma função referencia `job.fila`. Se o worker não rodar, o documento some da busca sem erro, sem alerta, sem log. | Médio — falha silenciosa, sem sinal para o operador. | Aberto — achado do veredito, "Observações com dono" item 1. |

## Itens do `arquiteto`

| # | Item | Risco se não resolvido | Status |
|---|---|---|---|
| A1 | **`deliberacoes.trecho_literal` é snapshot protegido por âncora móvel.** Mover `(documento_id, pagina)` para uma página pública torna o trecho legível. Local (a âncora está na mesma linha) e exige papel `editor` (que já pode publicar o que quiser — risco D4 já registrado), mas a semântica é frágil. | Baixo-médio, mitigado por já exigir papel privilegiado. | Aberto — observação do veredito, item 2. |
| A2 | **`documento_paginas` é tabela de autorização e não é auditada.** | Médio — tabela que decide visibilidade não deixa trilha de quem mudou o quê. | Aberto — observação do veredito, item 3. |
| A3 | **`unidades` não é auditada**, e `fracao_ideal` define rateio. | Médio — mudança de fração ideal sem trilha afeta cálculo financeiro de todos os condôminos. | Aberto — observação do veredito, item 4. |
| A4 | **Assinatura de parecer × anonimização de ex-morador.** `parecer_signatarios` guarda só `pessoa_id`; o nome do signatário vive só em `pessoas.nome`. Anonimizar um ex-morador que assinou parecer apaga o nome do signatário de um documento já emitido. Deliberadamente sem teste vermelho — decisão de produto/jurídica antes de travar comportamento. Dono conjunto `arquiteto` + `juridico-lgpd`. | Médio — tensão real entre LGPD (apagar PII) e integridade de documento histórico assinado. | Aberto — observação do veredito, item 5; precisa de decisão, não só de código. |

## Itens do `auditor-rls`

| # | Item | Risco se não resolvido | Status |
|---|---|---|---|
| R1 | **Corridas de concorrência fora do CI.** Não são expressáveis em pgTAP de transação única (`begin`/`rollback` por arquivo); verificadas por script de conexões paralelas rodado manualmente, fora do pipeline. | Médio — regressão de corrida (ex.: os cenários "resta 1" do V10) não é pega automaticamente. | Aberto — mecanismo de verificação manual, não automatizado. |
| R2 | **`deliberacoes` sem assert na suíte.** Verificado manualmente nas 3ª e 4ª rodadas; não codificado como teste. | Médio — mesma classe de risco de R1: verificação existe, mas não é regressiva. | Aberto. |

---

## Verificação de fechamento (item cobrado à parte pelo orquestrador)

O gate de CI (`ci-gate` em `.github/workflows/ci.yml`) precisa continuar rodando a suíte de RLS
em **toda** alteração de migração e barrar o merge de verdade — não só "rodar e reportar". Ver
`README.md` (seção CI/CD) para o desenho do gate e a pendência de branch protection no GitHub
(sem remoto ainda configurado). Esta linha é a mais importante da tabela: as quatro rodadas de
auditoria só valem para sempre se a regressão for barrada automaticamente daqui para frente.
