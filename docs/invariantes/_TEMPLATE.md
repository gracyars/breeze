# INV-<nn> — <enunciado da invariante em uma frase>

<!-- Copie este arquivo. Não apague seção. Célula vazia bloqueia o merge — ver README.md. -->

| Campo | Valor |
|---|---|
| **Enunciado formal** | `<predicado que deve valer SEMPRE, em SQL ou lógica>` |
| **Onde é usada** | `<policies, funções, triggers que dependem disto>` |
| **ADR de origem** | `<docs/adr/00XX-...md>` |
| **Migração** | `<supabase/migrations/...sql>` |
| **Dono** | `<agente>` |

## 1. Conjunto de dependência

Toda `tabela.coluna` que o predicado lê. Sai da leitura do corpo da função, não da memória.
Se o predicado chama outra função, o conjunto dela entra aqui.

| Tabela.coluna | Espécie (ADR-0023) | Justificativa da espécie |
|---|---|---|
| `<tabela>.<coluna>` | `local` / `constitutiva` / `modal` | … |

> **Se houver `modal`:** a primeira pergunta é como eliminá-la (ADR-0023, nível 0). Registre aqui a
> resposta, mesmo que seja "não dá, monotonizado" — com o motivo.

## 2. Matriz de caminhos de violação

Linhas geradas pelo produto cartesiano do conjunto acima — `INSERT`, `DELETE`, e **um `UPDATE` por
coluna** — mais as quatro linhas fixas. Vocabulário fechado no README.

| # | Caminho | Estado | Teste vermelho |
|---|---|---|---|
| 1 | `INSERT` em `<tabela>` | `GUARDADO(...)` | `<arquivo>::<nome do teste>` |
| 2 | `UPDATE` de `<tabela>.<coluna>` | | |
| 3 | `DELETE` em `<tabela>` | | |
| … | *(uma linha por coluna do conjunto)* | | |
| F1 | Escrita por `service_role` / worker | | |
| F2 | **Concorrência** — duas transações simultâneas | | |
| F3 | Restore, migração, backfill | | |
| F4 | Propriedade assumida por leitor (contiguidade, ordenação, unicidade) | | |

## 3. Nível da solução (ADR-0021)

- [ ] **0 — eliminada** (a invariante não existe mais)
- [ ] **1 — derivada** (o segundo caminho não existe)
- [ ] **2 — validada dos dois lados**
- [ ] **3 — invalidação/reprocessamento** (bloquear quebraria fluxo legítimo)

Se não for 0, **por que não**: …

## 4. O que fica aceito, e por quê

Todo `ACEITO(...)` da matriz reaparece aqui em prosa, com o argumento de por que não é vazamento.
Se esta seção estiver vazia e houver `ACEITO` na matriz, o arquivo está incompleto.
