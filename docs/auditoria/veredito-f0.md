# Veredito de auditoria — baseline F0 (`supabase/migrations/`)

**Auditor:** `auditor-rls` · **Data:** 2026-09-04 · **Rodadas:** 4
**Método:** ataque contra o banco real (`supabase_db_breeze`), não leitura de código. Todo teste
verde foi validado por mutação (quebrei a policy/o grant/o trigger/o predicado e confirmei que
fica vermelho). Nenhuma asserção foi aceita sem tê-la visto falhar quando devia falhar.

## VEREDITO: **APROVADO**

**Placar: 176 asserts — 176 verdes / 0 vermelhos.** Determinístico em 3 execuções consecutivas.
Banco sem resíduo (todo arquivo abre `begin` e fecha `rollback`).

| arquivo | asserts |
|---|---|
| `01_visibilidade_documento_pagina_chunk_rls.sql` | 47 |
| `02_papeis_aal_mandato_pessoas_cobrancas_rls.sql` | 51 |
| `03_lancamentos_audit_imutabilidade.sql` | 34 |
| `04_privilegios_grants_e_superficie.sql` | 31 |
| `05_trilha_pii_anonimizacao.sql` | 13 |

---

## Correção de um achado meu (3ª rodada)

O **V1-R2** que reportei — "apagar a única página com override abre o documento" — era **artefato
de uma anomalia, não vazamento**. O `arquiteto` estava certo, e verifiquei de três formas:

1. Na minha própria fixture, o `anon` já lia as páginas 5 e 6 **antes de qualquer `DELETE`**. O
   `DELETE` nunca foi o que abria.
2. Num documento de piso `publico`, o único override que o piso do ADR-0019 permite é `publico` —
   o override da minha página 3 era um **no-op semântico** que só servia para ligar o modo
   "misto" e fechar todas as outras páginas.
3. Com o piso, `documentos.visibilidade` é o nível mais restritivo que qualquer página daquele
   documento poderia ter. Herdar o piso **não pode afrouxar**. O ramo `documento_tem_override` não
   protegia nada e errava nas duas direções.

Eu estava travando um comportamento acidental como se fosse garantia. A conclusão certa não era
"conserte o `DELETE`" — era "elimine o ramo", que é o que o ADR-0023 fez.

---

## Localidade (ADR-0023) — a propriedade que substituiu "falha fechado"

> Escrever, alterar ou apagar a página X não pode mudar o nível efetivo **nem o acesso real** da
> página Y.

Testada nas duas camadas (predicado isolado **e** acesso por `anon`/`authenticated`, porque os
vazamentos das rodadas anteriores apareceram sempre pelo acesso, nunca pelo predicado sozinho).
`01` H1–H8: `INSERT`, `UPDATE` e `DELETE` de override numa página vizinha — inclusive apagar a
**última** página classificada — não alteram a assinatura de acesso das páginas 5 e 6.
Validado por mutação: reintroduzir `documento_tem_override()` derruba D2, H2, H4, H6 e H9.

### Varredura de não-localidade modal — a classe está fechada

Taxonomia do ADR-0023: **constitutiva** (as outras linhas *são* a decisão — legítima) vs.
**modal** (as outras linhas mudam *como* a regra se aplica — proibida). Varri o schema com um
harness que mede a assinatura de acesso de 4 papéis antes e depois de mutar cada tabela vizinha,
excluindo do fingerprint a entidade mutada e seus filhos.

| mutação | efeito sobre terceiros | julgamento |
|---|---|---|
| `documento_paginas` INSERT/UPDATE/DELETE (página vizinha) | nenhum | **local** |
| `tipos_documento.permite_publico` / `visibilidade_padrao` | nenhum | não é lida por predicado |
| `documentos.visibilidade`/`status` de outro documento | nenhum | local |
| `documento_unidades` de outro documento | nenhum | constitutiva, escopada |
| `pareceres.status` de outro parecer | nenhum | pai→filho, constitutiva |
| `configuracoes.publica` de outra chave | nenhum | local à linha |
| `pessoas.ativa` / `papeis` / `vinculos` de outra pessoa | só o próprio sujeito | constitutiva |
| `unidades.ativa` | nenhum | — |

**Nenhum modal remanescente.** Congelei o resultado em `04` G1 (conjunto exato de tabelas que
cada predicado pode ler), G2 (`nivel_efetivo` filtra `documento_paginas` pela página avaliada) e
G3 (nenhum predicado agrega sobre `documento_paginas`). G1 e G3 ficam vermelhos sob mutação.

**Storage é fail-closed nos dois sentidos** (verificado): objeto cujo documento foi apagado, e
objeto que deixou de ser apontado — nenhum dos dois é acessível.

---

## V10 — nove rotas testadas, nenhuma passa

O trigger passou a disparar em `UPDATE` inteiro (sem `OF <coluna>`) e a comparar o **estado
resultante** via `public.eh_editor_vigente_linha()`, com dois lookups de `pessoas.ativa`
(antes/depois) e advisory lock compartilhado entre `pessoas` e `papeis`.

| rota | resultado |
|---|---|
| `pessoas.ativa=false` · `mandato_fim` · `mandato_inicio` futuro · `papel`→morador | bloqueadas (P0001) |
| **transferir o papel para pessoa inativa** (4ª rota — exigia os dois lookups) | bloqueada |
| transferir para inativa mexendo no mandato junto | bloqueada |
| "designar" editor numa pessoa inativa e encerrar o próprio | bloqueada |
| `DELETE` de `papeis` / de `pessoas` | bloqueadas (42501) para `authenticated`; `service_role` não tem UPDATE/DELETE/TRUNCATE nessas tabelas |
| **corrida:** 2 transações desativando cada editor | uma passa, outra é bloqueada — resta 1 |
| **corrida mista:** T1 em `pessoas`, T2 em `papeis` | resta 1 |
| **corrida 4-way:** 4 rotas diferentes em paralelo | resta 1 |

**Não achei a 5ª rota.** Validado por mutação: voltar ao lookup único + gatilho por coluna derruba
F3, F4, F6, F7 e F10.

---

## Observações com dono (não bloqueiam)

1. **Documento some da busca em silêncio.** O `DELETE` de chunks do invalidador aposta no
   reprocessamento idempotente do worker, mas **nada no schema enfileira esse reprocessamento**:
   nenhuma função referencia `job.fila`. Se o worker não rodar, o documento sai da busca sem erro,
   sem alerta e sem log. **Dono:** `eng-supabase` — F1.
2. **`deliberacoes.trecho_literal` é um snapshot cuja proteção vem de uma âncora móvel.** Mover
   `(documento_id, pagina)` para uma página pública torna o trecho legível. É **local** (a âncora
   está na mesma linha) e exige papel `editor`, que já pode publicar o que quiser (risco D4 já
   registrado) — mas a semântica é frágil. **Dono:** `arquiteto`.
3. **`documento_paginas` é tabela de autorização e não é auditada.** **Dono:** `arquiteto`.
4. **`unidades` não é auditada** e `fracao_ideal` define rateio. **Dono:** `arquiteto`.
5. **Assinatura de parecer × anonimização.** `parecer_signatarios` guarda só `pessoa_id`; a
   identidade do signatário vive apenas em `pessoas.nome`. Anonimizar um ex-morador que assinou
   parecer apaga o nome do signatário de um documento emitido. Deliberadamente **sem teste
   vermelho**, para não prejulgar o ADR. **Dono:** `arquiteto` + `juridico-lgpd`.

---

## Fora de cobertura — dívida rastreada para F1

| item | por quê | dono |
|---|---|---|
| **Storage API real** (signed URL, TTL, checagem de papel no servidor que emite a URL) | testei só a RLS de `storage.objects`; o resto é código de aplicação | `eng-supabase` |
| **Emissão de `aal2` pelo GoTrue** | simulo o claim `aal` no JWT; não validei que o Auth só emite `aal2` após TOTP | `devops` |
| **Supabase hospedado** | o ACL de `service_role` medido é o do stack local; produção pode diferir | `devops` |
| **`pg_prove` / `supabase test db`** | ausente na máquina; validei o TAP com `psql -X -q --no-align --tuples-only`, modo equivalente | `devops` |
| **Corridas de concorrência na suíte** | não são expressáveis em pgTAP de transação única; verificadas por script de conexões paralelas, fora do CI | `auditor-rls` |
| **`deliberacoes`** | verificado manualmente nas 3ª e 4ª rodadas; sem assert na suíte | `auditor-rls` |

---

## O padrão, para a regra de revisão

Nas quatro rodadas, todo achado teve a mesma forma: **a invariante é validada na escrita de um
lado da relação e não é revalidada quando o outro lado muda.** Página × documento; chunk × página;
`mandato_fim` × as outras colunas que decidem vigência; página apagada × as páginas que sobraram.

A 4ª rodada acrescentou a lição mais útil: **a melhor correção não foi adicionar o gatilho que
faltava, foi eliminar a regra que exigia o gatilho.** `app.nivel_efetivo` puramente local não
precisa de revalidação porque não há nada a revalidar. Regra proposta para revisão de schema:

> Antes de adicionar um gatilho para manter duas tabelas coerentes, pergunte se o predicado
> precisava mesmo ler as duas. Predicado local não tem invariante distribuída para manter.
