# ADR-0012 — RLS como fronteira única de autorização; espelhamento obrigatório em tabela derivada

## Contexto

Não existe camada de API própria (ADR-0001): Server Components, Server Actions, worker e
PostgREST falam com o mesmo banco. Autorização escrita em código de aplicação teria que ser
reimplementada em cada um desses caminhos — e o caminho esquecido é o que vaza. **Armadilha nº1
do projeto** (SPEC §7, §8.1): RLS em `documentos` sem RLS equivalente em `chunks` e
`documento_paginas` vaza conteúdo restrito pela busca, que é justamente a funcionalidade central.

## Decisão

1. **A RLS do Postgres é a única fronteira de autorização.** Verificação em código de aplicação
   é ergonomia (esconder botão, dar mensagem melhor), nunca segurança. Se a RLS não impedir,
   não está impedido.
2. **Negação por padrão em toda tabela**, em todo schema, incluindo tabelas novas:
   `alter table ... enable row level security` **e** `force row level security`
   (esta última faz a policy valer também para o dono da tabela), mais
   `revoke all on ... from anon, authenticated` e `grant` explícito e mínimo por operação.
   Tabela sem policy é tabela inacessível — e é esse o estado inicial correto.
3. **Espelhamento por função, não por cópia de predicado.** Existe **uma** função
   `app.documento_visivel(documento_id uuid) returns boolean`. As policies de `documentos`,
   `documento_paginas`, `chunks`, `deliberacoes` e `storage.objects` chamam **essa mesma função**.
   Nenhuma delas reescreve a regra. É assim que o espelhamento deixa de depender de alguém
   lembrar: mudar a visibilidade é mudar uma função, e as cinco policies acompanham.
4. **Helpers em schema `app`, fora do PostgREST**, `SECURITY DEFINER`, `STABLE`, com
   `set search_path = ''` e referência qualificada a tudo (`SECURITY DEFINER` sem `search_path`
   fixo é escalada de privilégio):
   - `app.pessoa_atual() → uuid`
   - `app.tem_papel(p papel) → boolean` — **primitiva**; só reconhece `editor`/`conselho` com
     `aal2` no JWT (ADR-0003) e mandato vigente (`mandato_fim is null or >= current_date`)
   - `app.papel_atual() → papel` — papel mais forte vigente, para UI; **não** é a primitiva de RLS
   - `app.unidades_da_pessoa() → setof uuid` — vínculos vigentes
   - `app.documento_visivel(uuid) → boolean`
5. **Papel é dado, não claim.** Papel vive em `public.papeis` com mandato datado, não em
   `app_metadata` do JWT. Um mandato que termina hoje deixa de valer hoje, sem esperar a expiração
   do token. Custo: um lookup por avaliação — mitigado por `STABLE` (cache dentro da consulta) e
   índice apropriado.
6. **`service_role` não é escape hatch.** Ele contorna RLS por construção; portanto só o worker e
   rotinas de servidor explicitamente auditadas o usam, para operações que não dependem de
   identidade de usuário. Nenhuma Server Action que serve pedido de usuário usa `service_role`
   para "resolver" um problema de policy.
7. **Única exceção deliberada — privilégio de coluna:** `pessoas.cpf_enc` tem `REVOKE SELECT`
   para `authenticated`. RLS é por linha e não esconde coluna; aqui o privilégio de coluna
   complementa, e a chave de decifra fora do banco (ADR-0014) é a trava real.
8. **Teste pgTAP versionado por policy, rodando no CI como gate** (SPEC §7). Cobertura mínima
   por tabela: para cada papel (`anon`, `morador`, `morador de outra unidade`, `conselho`,
   `editor`) × cada operação (`select`, `insert`, `update`, `delete`), um teste que afirma o
   permitido **e** um que afirma o negado. Teste de negação é o que pega regressão; teste só do
   caminho feliz passa com RLS desligada.

## Consequências

- Toda consulta paga o custo da policy. Nesta escala é irrelevante; o cuidado necessário é ter
  índice nas colunas que a policy filtra (`documentos.visibilidade`, `vinculos(pessoa_id)`,
  `cobrancas.unidade_id`) — senão a policy vira varredura por linha.
- `app.documento_visivel()` é avaliada por linha em `chunks`. Com `STABLE` e mesmo argumento
  repetido, o custo é aceitável em ~milhares de chunks; se doer, a saída é desnormalizar
  `visibilidade` para `chunks` com trigger de sincronização — **desnormalização com trigger, nunca
  predicado duplicado à mão**.
- Bug de RLS é vazamento de dado pessoal, e o CI é o único lugar onde ele é pego antes do fato.
  Por isso o gate bloqueia merge (ADR-0008).
- Um agente que não consegue ler um dado deve corrigir a policy em migração revisada — nunca
  contornar por `service_role`. Esta frase existe porque o contorno é sempre o caminho mais curto.

## Alternativas descartadas

- **Autorização na aplicação (middleware/guards).** Exigiria reimplementação em Server Component,
  Server Action, worker e PostgREST. Um caminho esquecido = vazamento.
- **PostgREST desligado, tudo por Server Action.** Reduz superfície, mas não elimina: a Server
  Action ainda precisa de uma fronteira, e sem RLS ela seria código. Além disso perde o acesso
  direto que simplifica leitura. A RLS continua sendo necessária de todo jeito.
- **Predicado de visibilidade copiado em cada policy.** É literalmente a armadilha nº1: cópia
  diverge na primeira alteração, e diverge em silêncio.
- **Papel no JWT (`app_metadata`).** Mais rápido, mas revogação passa a depender de expiração de
  token — inaceitável para `editor`/`conselho`.
- **Views `security_definer` como camada de acesso.** Esconde a fronteira e dificulta o teste
  pgTAP por papel. Views aqui são conveniência de leitura (`security_invoker`), não autorização.

## Status

Aceito. **Estendido pelo ADR-0018** (visibilidade por página em documento de conteúdo misto):
o item 3 acima pressupunha que visibilidade é propriedade do documento, o que o acervo real
desmentiu. A regra de "uma função só" permanece — o núcleo do mapeamento nível → papel continua
em `app.nivel_visivel`; mudou o que as funções de entrada recebem. O item 7 (exclusão de coluna)
é corrigido no mecanismo pelo **ADR-0017**: `REVOKE` de coluna não subtrai de `GRANT` de tabela;
usa-se `GRANT SELECT` com lista explícita de colunas.
