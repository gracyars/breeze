# ADR-0026 — Quem invalida, enfileira: reprocessamento é obrigação do banco, não promessa do worker

> Fecha a dívida **E2** de `docs/ops/divida-tecnica.md` (achado 1 das "Observações com dono" do
> `veredito-f0.md`): *"documento some da busca em silêncio"*.

## Contexto

`tg_documento_paginas_invalida_chunks_afetados` (baseline 08) **apaga** os chunks que deixaram de
ser uniformes quando uma página é reclassificada. Apagar é a decisão certa (ADR-0021, nível 3:
invalidar o derivado em vez de bloquear o fluxo legítimo). O problema é o que vem depois: o
comentário da função diz *"o worker recria o chunk certo"* — e **nada no schema pede isso ao
worker**. Nenhuma função em toda a baseline referencia `job.fila`.

O resultado é uma falha silenciosa perfeita: o `DELETE` funciona, a transação commita, nenhum erro
aparece, e o documento sai da busca. Sem log, sem alerta, sem status diferente. A pessoa só
descobre quando procura por um trecho que sabe existir e não acha — e a conclusão dela não vai ser
"o índice quebrou", vai ser "esse produto não acha as coisas".

E há um agravante que torna isto **bloqueante para F1**, não uma pendência de higiene: o caso que
motivou o modelo inteiro de visibilidade por página (D11) é a ata AGE de 04.02.2026 com o Regimento
embutido. O fluxo real dela é, obrigatoriamente:

1. worker chunkiza as 36 páginas (todas `autenticado` — nenhum chunk cruza fronteira, nenhum erro);
2. a curadoria marca as páginas do regimento como `publico`;
3. o invalidador apaga os chunks que cruzam a fronteira 13/14;
4. **alguém precisa rechunkizar** — e hoje esse alguém não existe.

Sem este ADR, o documento que justifica o modelo termina com um buraco na busca e ninguém percebe.

## Decisão

### 1. Uma função de enfileiramento, e ela é o único jeito de enfileirar

`job.enfileirar(p_tipo text, p_documento_id uuid, p_chave text, p_payload jsonb, p_prioridade int)`,
`SECURITY DEFINER`, no schema `job`. Faz `insert ... on conflict (chave_idempotencia)
where status in ('pendente','processando') do nothing` — com a unicidade parcial do ADR-0025, sem
a qual este `on conflict` seria um no-op permanente.

**Todos os caminhos de enfileiramento passam por ela.** Enumerados, porque enumerar é o método
(ADR-0021):

| # | Quem enfileira | Quando |
|---|---|---|
| 1 | Server Action de upload | documento novo (estágio 1) |
| 2 | O próprio worker | ao concluir um estágio, enfileira o próximo, no mesmo commit |
| 3 | **Trigger invalidador de chunks** | página reclassificada — **é o que falta hoje** |
| 4 | Curadoria: "rodar OCR nesta página" | ação humana explícita |
| 5 | Comando de reprocessamento (`--estagio`, `--onde`) | correção de pipeline, ligar embedding |
| 6 | Botão "tentar de novo" num documento em `erro` | recuperação de job `morto` |

É a mesma razão do ADR-0012 para ter **uma** função de visibilidade: seis lugares construindo
payload e chave à mão divergem, e divergem calados.

### 2. O invalidador chama `job.enfileirar` na mesma transação em que apaga

`tg_documento_paginas_invalida_chunks_afetados` passa a, depois do `DELETE`, chamar
`job.enfileirar('chunking', documento_id, ...)`. Atomicidade de graça: a fila está no mesmo banco.
**Não existe estado "apagou e não pediu para refazer".** Esta é a propriedade que o ADR-0007
comprou ao pôr a fila em Postgres e que ninguém tinha cobrado.

### 3. O sinal de "fora da busca" é uma coluna própria, não o `status` do documento

Tentação óbvia: mandar o documento de volta para `status = 'processando'`. **Errado, e de um jeito
caro:** a RLS do morador exige `status = 'publicado'`. Rebaixar o status faz o documento
**desaparecer inteiro** da UI — não só da busca — porque uma página foi reclassificada. Troca uma
falha silenciosa por uma falha barulhenta e pior.

Publicação (decisão de curadoria) e indexação (estado da máquina) são **dois eixos ortogonais** e
não cabem num enum só.

Decisão: `documentos.indexado_em timestamptz` — escrita pelo estágio de chunking/indexação,
**zerada pelo invalidador na mesma transação**. Local à linha (ADR-0023): nenhuma agregação sobre
`chunks`, nenhum `exists` sobre outras linhas.

- `indexado_em is null` **e** documento publicado ⇒ a UI mostra **"reindexando"** no documento e no
  resultado de busca, como o SPEC §3 já exige. O documento continua legível e baixável; só a busca
  está temporariamente incompleta, e ela **diz isso**.
- Nunca afeta autorização. É sinal de estado, não predicado de acesso.

### 4. A sentinela: a pergunta que ninguém estava fazendo

Enfileirar não é processar. O trigger pode cumprir seu papel e o worker estar desligado há uma
semana. Então existe uma consulta única, com nome, que responde **"o que está fora da busca agora
e não tem ninguém encarregado de trazer de volta?"**:

```
documento publicado
  ∧ indexado_em is null
  ∧ não há job pendente ou processando para ele
```

Materializada como view `app.documentos_fora_da_busca` (leitura só para gestão), exposta em três
lugares — porque uma sentinela que só existe numa view é uma sentinela que ninguém lê:

1. **Na tela de acervo da editora**, como faixa: "3 documentos estão fora da busca".
2. **No arranque e a cada ciclo do worker**, no log, com contagem — é onde a mantenedora olha.
3. **No runbook**, como comando SQL de verificação, junto com o teste trimestral de restore.

A segunda linha, mais fraca, também vale registrar: `indexado_em is null` **com** job pendente há
mais de 48 h significa "worker parado", não "defeito" — e o texto para a pessoa é outro ("ligue o
ingestor"), não um alarme.

### 5. Dono, por peça

| Peça | Dono |
|---|---|
| `job.enfileirar`, alteração do trigger invalidador, coluna `indexado_em`, view sentinela, índice parcial da `chave_idempotencia` | `eng-supabase` |
| Formulário **INV-13** (invariante nova, abaixo) e testes vermelhos em pgTAP | `eng-supabase` escreve, `auditor-rls` testa |
| Chamada de `job.enfileirar` pelos caminhos 1, 4, 5 e 6; leitura de `indexado_em` na UI | quem construir a aplicação de F1 |
| Sentinela no log do worker e no runbook | `devops` |

### 6. Isto é uma invariante de dois lados, e ganha formulário

Enunciado para `docs/invariantes/INV-13`:

> **Derivado invalidado implica reconstrução enfileirada.** Se existe documento publicado com
> `indexado_em is null`, então existe job `pendente`/`processando` de `chunking` para ele — ou a
> sentinela o está mostrando.

Matriz `(tabela × operação)` obrigatória, incluindo as quatro linhas fixas do ADR-0023/D16
(`service_role`, concorrência, restore/migração, propriedade assumida por leitor). Duas células que
já se sabe existirem e que a geração mecânica obriga a responder:

- **`DELETE` direto em `chunks` por `service_role`** (o worker tem esse `GRANT`): o caminho existe e
  não passa pelo invalidador. Resposta prevista: `ACEITO`, com argumento — é o próprio worker
  reconstruindo, dentro da transação que insere de novo; a sentinela pega se ele morrer no meio.
- **Restore de backup:** a fila é restaurada junto (está no `pg_dump`, ADR-0007), então jobs
  pendentes voltam. Mas job `processando` no momento do dump volta com lease vencida — o varredor
  do ADR-0025 resolve. Célula `GUARDADO`, com o varredor como guarda.

Testes vermelhos mínimos: (a) reclassificar página apaga chunk **e** cria job — falha se o job não
existir; (b) com o worker parado, o documento aparece na sentinela; (c) rodar o worker esvazia a
sentinela e `indexado_em` volta a ser preenchido; (d) reenfileirar duas vezes cria **um** job
pendente (não zero, que é o bug da unicidade total, e não dois).

## Consequências

- O caso da ata AGE (D11) passa a funcionar de ponta a ponta pela primeira vez. Antes deste ADR o
  modelo de visibilidade por página estava correto na leitura e incompleto na escrita.
- A busca ganha um estado honesto — "reindexando" — em vez de silenciosamente incompleta. É pior
  esteticamente e muito melhor para a única coisa que o produto vende, que é confiança.
- O worker deixa de ser a única fonte de trabalho: o banco passa a **exigir** trabalho. Isso é
  desejável e tem um custo: um trigger que enfileira pode multiplicar jobs se alguém reclassificar
  100 páginas em massa. Mitigado pelo `on conflict do nothing` sobre a chave parcial — 100 páginas
  do mesmo documento geram **um** job de chunking, não 100.
- `indexado_em` é a terceira coluna de estado em `documentos` (`status`, `erro_detalhe`,
  `indexado_em`). Aceito conscientemente: são três eixos diferentes (curadoria, falha, índice), e
  colapsá-los foi justamente o erro que este ADR evita.

## Alternativas descartadas

- **Deixar o worker varrer "documentos sem chunks" periodicamente.** É a alternativa mais óbvia e
  a pior: transforma uma obrigação atômica numa varredura eventual, exige agregação sobre `chunks`
  (a tabela mais lida), e o intervalo da varredura vira uma janela de busca incompleta que ninguém
  escolheu. Pior ainda, continua silenciosa: se a varredura não rodar, nada acusa.
- **Rebaixar `documentos.status` para `processando`.** Some com o documento inteiro da UI do
  morador por causa da RLS. Detalhado no item 3.
- **Marcar o chunk como inválido em vez de apagar.** Já descartado no ADR-0021/D15, e pelo motivo
  mais forte que existe: exigiria lembrar de `and invalidado_em is null` em toda consulta — linha
  apagada não vaza, linha marcada vaza no dia em que alguém esquecer o filtro.
- **Notificação por `LISTEN`/`NOTIFY` em vez de linha na fila.** `NOTIFY` não sobrevive a worker
  desligado: a mensagem se perde e não há o que reprocessar. Fila é durável; notificação é dica.
  (Como **aceleração** de latência, sobre a fila durável, é aceitável no futuro — nunca no lugar
  dela.)
- **Alerta por e-mail a cada invalidação.** Ruído: reclassificar páginas é fluxo normal de
  curadoria. O que merece alerta é a sentinela **persistente**, não o evento.

## Status

Aceito, 2026-09-06. Fecha E2. Depende da unicidade parcial de `chave_idempotencia` (ADR-0025 §2).
Artefato de verificação: `docs/invariantes/INV-13`.
