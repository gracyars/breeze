# ADR-0009 — Política de ambientes e de dados por ambiente

## Contexto

Três ambientes (SPEC §1.2): local, staging, produção. O dado de produção é dado pessoal de
vizinhos reais — nome, unidade, CPF, situação de inadimplência. Um dump de produção copiado para
staging "só para testar" é um incidente LGPD, e é a coisa mais natural do mundo de se fazer
quando há um mantenedor só e pressa.

## Decisão

| Ambiente | Infra | Dado | Quem aplica migração |
|---|---|---|---|
| **local** | `supabase start` (Docker) | seed sintético, gerado por script | o agente/dev, livremente |
| **staging** | Supabase Free + preview da Vercel | seed sintético + **dump anonimizado** de produção | CI, no merge para `main` |
| **produção** | Supabase Pro + Vercel produção | dado real | CI, em release marcada |

Regras duras:

1. **Dado de produção nunca é copiado cru para staging ou local.** O que trafega é dump
   **anonimizado**: CPF regenerado, e-mail redirecionado a domínio-sumidouro, nome substituído,
   `cpf_enc` descartado (não re-cifrado — a chave de produção não sai de produção, ADR-0014),
   `audit.log` truncado. A rotina de anonimização é código versionado e roda **dentro** de
   produção, exportando já anonimizado; nunca "exporta e depois limpa".
2. **Segredos por ambiente, sem interseção.** `CPF_PEPPER`, `CPF_ENC_KEY`, `SERVICE_ROLE_KEY`,
   credencial do worker: valores distintos em cada ambiente. Consequência aceita: um CPF
   pesquisado em staging não tem o mesmo `cpf_hash` de produção — correto, é o objetivo.
3. **Pepper e chave de cifra jamais entram no repositório, no banco ou em log.** Vivem no
   gerenciador de segredos da plataforma. Rotação exige recomputar `cpf_hash`/`cpf_enc` de toda a
   tabela `pessoas` (procedimento documentado em runbook — ver ADR-0014).
4. **Preview da Vercel aponta para staging, nunca para produção.** Um preview de PR com credencial
   de produção é acesso a dado real por URL não listada.
5. **Backup é de produção e é do projeto, não do provedor** (SPEC §7): `pg_dump` semanal +
   espelho do Storage **em conta separada**, com restore testado trimestralmente em ambiente
   descartável. Restore não testado não é backup.
6. **Staging pode ser destruído e recriado a qualquer momento.** Nada que só existe em staging é
   confiável.
7. Retenção diferenciada em produção: `audit.log` permanente (ADR-0013); `audit.acesso`,
   6 meses (SPEC §7); dado de ex-morador passa por anonimização preservando agregados.

## Consequências

- Staging em plano Free pausa por inatividade e não tem PITR — aceitável, porque nada de valor
  vive só lá (regra 6). Se um dia a equipe crescer, staging vira Pro e o custo do §1.2 muda:
  isso exige escalar.
- Testar um bug que só aparece com dado real fica mais caro. É o preço; a alternativa é copiar
  dado pessoal, que não está disponível.
- O CI precisa de um banco efêmero para `supabase db reset` + pgTAP a cada PR. Custo: minutos de
  runner, não infraestrutura.
- Bus factor = 1 (Risco §8.5): o runbook de restauração e o export completo em um comando são
  entregáveis de F0, não de F4 — sem eles, os segredos e o acesso morrem com uma pessoa.

## Alternativas descartadas

- **Dois ambientes (local + produção).** Sem staging, o teste de RLS roda só contra banco vazio
  local e a primeira validação com dado plausível acontece com dado real. Descartado.
- **Supabase Branching (branch de banco por PR).** Atraente para o fluxo de migração, mas
  multiplica projetos e custo, e a versão gerenciada ainda amarra o preview a dado de produção
  se mal configurada. Reavaliar quando houver mais de um desenvolvedor humano.
- **Dump de produção em staging com "acesso restrito".** Restrição de acesso não é anonimização;
  não sobrevive a uma pergunta do titular do dado.
- **Confiar no backup do provedor.** "Backup do provedor não é backup" (SPEC §7): a mesma conta
  comprometida perde os dois.

## Status

Aceito.
