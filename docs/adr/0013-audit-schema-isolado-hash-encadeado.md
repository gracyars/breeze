# ADR-0013 — Trilha de auditoria em schema `audit` isolado, append-only, com hash encadeado

## Contexto

O produto é uma camada de fiscalização (Briefing §1), e quem opera o sistema é quem seria
auditada (D4, Risco §8.6). Uma trilha que a própria `editor` possa reescrever não sustenta nada.
O objetivo não é impedir adulteração — quem tem acesso ao banco sempre pode escrever nele — mas
tornar a adulteração **detectável por um terceiro**, sem depender de confiar no operador.

## Decisão

### Isolamento

Schema `audit`, **fora do PostgREST** (`db.exposed_schemas` no `config.toml` lista apenas
`public`, `storage`, `graphql_public`). `revoke all on schema audit from public, anon,
authenticated`. Ninguém lê a trilha pela API; a leitura acontece por rotina de servidor
autorizada, e o resultado exposto ao `conselho` é uma view somente-leitura filtrada.

`REVOKE UPDATE, DELETE ON audit.log FROM PUBLIC` **inclusive para `service_role`** (SPEC §2),
mais trigger `BEFORE UPDATE OR DELETE` que levanta exceção — porque `REVOKE` não alcança
superusuário nem o dono da tabela.

### Encadeamento

```
hash_registro = sha256( coalesce(hash_anterior, '\x00'::bytea) || canonico )
canonico      = convert_to( jsonb_build_object(
                    'seq', seq, 'ts', ts, 'actor_uid', actor_uid, 'acao', acao,
                    'schema', schema_nome, 'tabela', tabela, 'registro_id', registro_id,
                    'antes', antes, 'depois', depois )::text, 'UTF8' )
```

A serialização canônica é **parte do contrato** e está fixada em `schema.md`: `jsonb` ordena e
deduplica chaves de forma determinística, o que torna o hash reproduzível por qualquer verificador
que leia a linha. Mudar a serialização quebra a cadeia — logo, é migração com ADR novo e âncora
de corte, nunca ajuste.

**Serialização de escrita:** o trigger toma `pg_advisory_xact_lock` sobre uma chave fixa antes de
ler o último `hash_registro`. Sem isso, duas transações concorrentes leem o mesmo `hash_anterior`
e a cadeia bifurca — falha que só aparece sob carga e destrói a garantia em silêncio. O custo é
serializar as escritas auditadas; nesta escala (dezenas de escritas/dia) é irrelevante.

### Âncora externa

`audit.ancoras` guarda o hash-topo semanal; uma rotina envia esse hash por e-mail ao conselho
(SPEC §7). O e-mail sai do sistema e fica na caixa de terceiros: é o que impede reescrever o
passado **e** recomputar a cadeia inteira para casar. Sem âncora externa, a hash-chain só protege
contra edição desatenta.

### Escopo

Auditadas (trigger `AFTER INSERT/UPDATE/DELETE FOR EACH ROW`): `pessoas`, `papeis`, `vinculos`,
`documentos`, `lancamentos`, `lancamento_anexos`, `orcamento`, `cobrancas`, `fornecedores`,
`fornecedor_dados_bancarios`, `contratos`, `deliberacoes`, `configuracoes`, `periodos_fechados`,
`questionamentos`, `pareceres`.

**Não** auditadas: `chunks`, `documento_paginas`, `job.fila` — saída determinística de máquina,
alto volume, sem intenção humana a registrar. Reproduzíveis do PDF original.

### Log de acesso é outra coisa

`audit.acesso` (tabela separada, **sem** encadeamento) registra leitura de dado sensível —
inadimplência nominal, CPF em claro, export (SPEC §5.5, §7). Separada de propósito: a retenção do
log de acesso é de 6 meses (SPEC §7), e **expurgo é incompatível com cadeia de hash**. Misturar as
duas obrigaria a escolher entre violar a retenção e quebrar a cadeia.

## Consequências

- Adulteração por quem tem acesso ao banco fica detectável, inclusive pela própria `editor`.
  É isso que dá ao produto autoridade perante os moradores (SPEC §7).
- `audit.log` cresce sem expurgo. Nesta escala (dezenas de escritas/dia) são poucos MB/ano.
- Escritas auditadas ficam serializadas pelo advisory lock: transação longa que escreve em tabela
  auditada bloqueia as demais. Regra operacional: importação em lote (backfill, balancete) roda
  em transações pequenas.
- `antes`/`depois` em `jsonb` copiam a linha inteira — inclusive `cpf_hash` e `cpf_enc`. Decisão:
  o trigger **redige colunas sensíveis** (`cpf_enc` vira `'[redigido]'`), senão a trilha vira uma
  segunda cópia irremovível de dado pessoal, sujeita a direito de eliminação que ela não pode
  atender.
- `verificar_cadeia(desde, ate)` recalcula e aponta a primeira linha inconsistente. Roda semanal,
  antes da âncora, e sob demanda.

## Alternativas descartadas

- **`audit.log` no schema `public` com RLS.** RLS não protege de `service_role`, e a tabela ficaria
  exposta pelo PostgREST. Isolamento de schema é a fronteira mais barata e mais auditável.
- **Trilha só por `pgaudit`/logs do servidor.** Registra comando, não estado antes/depois; fica no
  provedor, sob controle de quem opera; não é encadeada e não é consultável pelo conselho.
- **Sem encadeamento, só `INSERT` com `REVOKE`.** Protege contra acidente, não contra intenção.
  Todo o valor está em detectar quem tem privilégio.
- **Assinatura digital por linha em vez de encadeamento.** Requer chave privada disponível ao
  banco ou a cada escrita — mais superfície, e não resolve remoção de linha (a cadeia resolve).
- **Blockchain/serviço externo de timestamping por evento.** Custo e dependência
  desproporcionais; a âncora semanal por e-mail entrega a mesma propriedade prática.
- **Um só log para mutação e acesso.** Incompatível com a retenção de 6 meses do log de acesso.

## Status

Aceito.
