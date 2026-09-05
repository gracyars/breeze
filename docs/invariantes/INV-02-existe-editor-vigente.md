# INV-02 — Existe sempre ao menos uma pessoa ativa com papel `editor` vigente

> **Exemplo preenchido de referência.** É o caso do **V10**, escolhido de propósito: a guarda
> original vigiava `papeis.mandato_fim` e passaram `mandato_inicio`, `papel` e a corrida
> concorrente. Preenchida a matriz, as células vazias aparecem — e apareceu **uma quarta** que
> ninguém tinha nomeado (linha 7).

| Campo | Valor |
|---|---|
| **Enunciado formal** | `count(*) >= 1` sobre `pessoas p join papeis pa on pa.pessoa_id = p.id` onde `p.ativa` e `pa.papel = 'editor'` e `pa.mandato_inicio <= current_date` e `(pa.mandato_fim is null or pa.mandato_fim >= current_date)` |
| **Onde é usada** | `app.tem_papel('editor')` → toda escrita do schema. Se cair a zero, o sistema fecha para sempre |
| **ADR de origem** | `docs/adr/0022-ultimo-editor-nao-desativavel.md` |
| **Migração** | *(a criar — `eng-supabase`)* |
| **Dono** | `eng-supabase` (implementação) · `auditor-rls` (testes) |

## 1. Conjunto de dependência

| Tabela.coluna | Espécie (ADR-0023) | Justificativa da espécie |
|---|---|---|
| `pessoas.ativa` | constitutiva | é parte da decisão de quem tem papel vigente |
| `papeis.pessoa_id` | constitutiva | liga o papel à pessoa cuja atividade conta |
| `papeis.papel` | constitutiva | o valor `editor` é o objeto da invariante |
| `papeis.mandato_inicio` | constitutiva | define vigência |
| `papeis.mandato_fim` | constitutiva | define vigência |

Nenhuma dependência **modal**. Não-localidade aqui é intencional e permanece: a invariante é, por
natureza, uma contagem sobre um conjunto (ADR-0023, nível 1 — manter e guardar, **nunca**
monotonizar: mandato precisa poder terminar).

## 2. Matriz de caminhos de violação

| # | Caminho | Estado | Teste vermelho |
|---|---|---|---|
| 1 | `INSERT` em `pessoas` | `IMPOSSÍVEL(inserir pessoa não remove editor; a contagem só cresce)` | `02_papeis...::insert_pessoa_nao_reduz_editores` |
| 2 | `UPDATE` de `pessoas.ativa` (`true → false`) | `GUARDADO(pessoas_preserva_ultimo_editor)` | `::desativar_ultima_editora_falha` |
| 3 | `DELETE` em `pessoas` | `GUARDADO(papeis_preserva_ultimo_editor via ON DELETE CASCADE)` — ver §4 | `::deletar_ultima_editora_falha` |
| 4 | `INSERT` em `papeis` | `IMPOSSÍVEL(só aumenta a contagem)` | `::insert_papel_nao_reduz_editores` |
| 5 | `UPDATE` de `papeis.papel` (`editor → morador`) | `GUARDADO(papeis_preserva_ultimo_editor)` | `::rebaixar_ultima_editora_falha` ← **estava vazia (V10)** |
| 6 | `UPDATE` de `papeis.mandato_inicio` (para data futura) | `GUARDADO(papeis_preserva_ultimo_editor)` | `::adiar_mandato_da_ultima_editora_falha` ← **estava vazia (V10)** |
| 7 | `UPDATE` de `papeis.pessoa_id` (transferir para pessoa inativa) | `GUARDADO(papeis_preserva_ultimo_editor)` | `::transferir_papel_para_inativa_falha` ← **quarta lacuna, achada ao preencher** |
| 8 | `UPDATE` de `papeis.mandato_fim` (para o passado) | `GUARDADO(papeis_preserva_ultimo_editor)` | `::encerrar_mandato_da_ultima_editora_falha` |
| 9 | `DELETE` em `papeis` | `GUARDADO(papeis_preserva_ultimo_editor)` | `::deletar_ultimo_papel_editor_falha` |
| F1 | Escrita por `service_role` / worker | `GUARDADO(trigger roda para qualquer role, inclusive dono e service_role)` | `::service_role_nao_desativa_ultima_editora` |
| F2 | **Concorrência** — duas transações simultâneas | `GUARDADO(pg_advisory_xact_lock na chave 'editor_vigente' antes da contagem)` | `::duas_sessoes_encerrando_editores_distintos` ← **estava vazia (V10)** |
| F3 | Restore, migração, backfill | `ACEITO(pg_restore --disable-triggers ignora a guarda)` — ver §4 | `::smoke_pos_restore_conta_editores` |
| F4 | Propriedade assumida por leitor | `ACEITO(vigência usa current_date no fuso do servidor)` — ver §4 | `::vigencia_respeita_fuso_do_servidor` |

## 3. Nível da solução (ADR-0021)

- [x] **2 — validada dos dois lados** (`pessoas` e `papeis`)

**Por que não o nível 0 (eliminar):** a invariante existe porque o produto tem um papel com escrita
única (D4). Eliminá-la seria exigir dois editores — decisão da dona do projeto, não do arquiteto
(Briefing §7 item 2). Se um dia houver dois editores por política, esta invariante fica trivial e
pode ser reavaliada.

**Por que não o nível 1 (derivar):** não há fonte de verdade única de onde derivar "existe editor";
é uma contagem sobre duas tabelas por natureza.

## 4. O que fica aceito, e por quê

**Linha 3 — `DELETE` em `pessoas`.** Não é caminho direto: `papeis.pessoa_id` é
`on delete cascade`, então apagar a pessoa dispara `DELETE` em `papeis`, e **triggers `BEFORE
DELETE` em `papeis` rodam durante o cascade**. Por isso a guarda vive em `papeis` e cobre os dois.
Registrado explicitamente porque é contraintuitivo: quem procurar a guarda em `pessoas` não a acha,
e pode concluir que o caminho está aberto.

**F3 — Restore.** `pg_restore --disable-triggers` desliga a guarda por construção; nenhuma trigger
resolve isso. Não é vazamento — é operação de `devops` com runbook. A contenção é o smoke test
pós-restore que conta editores vigentes e falha alto se der zero. **Item de runbook**, não de
schema.

**F4 — Fuso.** A vigência usa `current_date` no fuso do servidor. Num condomínio único, em um só
fuso, a janela de erro é de horas no dia da virada de mandato e não produz estado irreversível — na
pior hipótese a guarda é *mais* restritiva por algumas horas. Aceito conscientemente; se o produto
virar multi-fuso, revisar.
