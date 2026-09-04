# ADR-0015 — Enum nativo para conjunto fechado; tabela de domínio para conjunto operacional

## Contexto

O schema tem vários conjuntos de valores fixos: papel, visibilidade, status de documento,
natureza de conta, tipo de documento, tipo de alerta, tipo de anexo. Em Postgres há três formas
de representá-los, e a escolha é difícil de reverter depois que há dado: `enum` nativo,
`text` + `CHECK`, ou tabela de referência com chave estrangeira.

O ponto que decide: **quem altera o conjunto e com que frequência.** Enum nativo aceita
`ADD VALUE` facilmente, mas **remover ou renomear valor exige recriar o tipo e reescrever toda
coluna que o usa** — caro com dado. Tabela de domínio é alterável em runtime, mas perde a
garantia em nível de tipo e adiciona um join a toda consulta.

## Decisão

**Enum nativo** para conjunto que só muda por decisão de arquitetura, com ADR:

`papel` (editor, conselho, morador), `visibilidade_documento`, `status_documento`,
`natureza_conta`, `tipo_lancamento`, `fundo`, `origem_lancamento`, `status_cobranca`,
`tipo_vinculo`, `severidade_alerta`, `status_alerta`, `status_questionamento`,
`tipo_assembleia`, `status_job`.

**Tabela de domínio** para conjunto que a operação altera sem migração:

`tipos_documento` (a taxonomia documental cresce: laudo novo, tipo novo de contrato),
`tipos_alerta` (o motor ganha regras), `contas` (o plano espelha a administradora e muda com
ela), `sinonimos`, `configuracoes`.

Regras que acompanham:

1. **`papel` é enum, e o enum tem exatamente três valores.** `sindico_terceirizado` **não entra**
   (D3): valor de enum é convite a criar conta. Ele é `fornecedores.eh_sindico_terceirizado`,
   um atributo da entidade fiscalizada.
2. Tabela de domínio carrega os atributos que a regra de negócio precisa, não só o rótulo:
   `tipos_documento.permite_publico` e `visibilidade_padrao` alimentam o trigger de visibilidade
   (ADR-0004); `contas.exige_deliberacao` alimenta o alerta de fundo sem ata.
3. **Valor de enum nunca é removido.** Deprecar é parar de usar e bloquear na aplicação; remover
   é migração com ADR próprio.
4. Enums vivem em `public` (o gerador de tipos TypeScript os traduz para union types — ganho
   direto de tipagem que a tabela de domínio não dá).
5. Nada de `text` + `CHECK (x IN (...))` para conjunto reusado em mais de uma tabela: o `CHECK`
   é copiado e diverge. Aceitável apenas para conjunto local de uma coluna só
   (ex.: `documento_paginas.fonte_texto`).

## Consequências

- Ganho de tipagem ponta a ponta: papel e visibilidade viram union type no TypeScript, e o
  compilador pega o `switch` incompleto.
- Adicionar valor de enum é `ALTER TYPE ... ADD VALUE` — em Postgres moderno funciona em
  transação, mas o valor novo **não pode ser usado na mesma transação**. Detalhe que quebra
  migração que adiciona e popula junto: precisam ser duas migrações.
- Toda leitura de `documentos.tipo` paga um join com `tipos_documento` quando precisa do rótulo.
  Irrelevante nesta escala, e o benefício (mudar taxonomia sem deploy) é grande.
- `contas` como tabela é obrigatório por outro motivo, independente deste ADR: o plano espelha
  1:1 o da administradora, e renomear conta destrói comparabilidade histórica (skill
  `condominio-plano-de-contas` §8). Mudança de plano é **evento de migração registrado**, com o
  histórico preservado sob o plano vigente à época.

## Alternativas descartadas

- **Tudo em tabela de domínio.** Perde a tipagem no TypeScript e transforma `papel` — a coisa
  mais sensível do modelo — em linha editável em runtime. Papel novo deve exigir migração e
  revisão de RLS, não um `INSERT`.
- **Tudo em enum nativo.** Adicionar um tipo de documento passaria a exigir deploy. A `editor` é
  uma pessoa só (D4); o gargalo de publicação já é humano, não pode depender também de CI.
- **`text` livre + validação na aplicação.** Sem fronteira no banco, o dado sujo entra pelo
  worker ou por qualquer rotina que esqueça a validação.

## Status

Aceito.
