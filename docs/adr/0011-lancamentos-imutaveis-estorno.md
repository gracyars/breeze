# ADR-0011 — `lancamentos` imutável; correção por estorno com contra-lançamento de valor negativo

## Contexto

SPEC §2 e §5.4: `lancamentos` **sem UPDATE/DELETE**, correção **sempre por estorno**. A razão não
é técnica, é política: quem publica é também quem seria auditada (Risco §8.6, D4 — `editor`
única). Se a editora puder corrigir um lançamento em silêncio, o balancete publicado deixa de ser
prova e vira afirmação — que é exatamente a dor nº2 do briefing.

A decisão em aberto era **como** modelar o estorno: (a) coluna de referência ao lançamento
estornado, na própria `lancamentos`; (b) tabela `estornos` separada; (c) versionamento
(`valid_from`/`valid_to`) com linha corrente.

## Decisão

**(a) — o estorno é um lançamento comum na própria tabela `lancamentos`**, com:

```
estorna_lancamento_id  uuid unique references lancamentos(id)  -- self-FK, null no lançamento normal
motivo_estorno         text                                    -- obrigatório no estorno, >= 10 chars
```

e **valor com sinal invertido**:

```sql
check (
  (estorna_lancamento_id is     null and valor_centavos > 0) or
  (estorna_lancamento_id is not null and valor_centavos < 0)
)
```

Invariantes garantidas por trigger (`schema.md`, `lancamentos_valida_estorno`):

1. `valor_centavos` do estorno = `-valor_centavos` do original, exato.
2. Estorno herda `conta_id`, `tipo` e `fundo` do original — estorno não reclassifica. Corrigir a
   conta é estornar e lançar de novo, e o par fica visível.
3. **Estorno de estorno é proibido** (o alvo precisa ter `estorna_lancamento_id is null`).
4. **Um lançamento é estornado no máximo uma vez** (`unique` na self-FK).
5. Estorno herda `documento_id`/`pagina_origem` do original quando não houver documento novo —
   nenhum lançamento existe sem fonte (SPEC §5.1.4).

Bloqueio de mutação, em três camadas independentes:

- `REVOKE UPDATE, DELETE ON public.lancamentos FROM anon, authenticated;`
- ausência de policy de `UPDATE`/`DELETE` (RLS nega por padrão — ADR-0012);
- trigger `BEFORE UPDATE OR DELETE` que levanta exceção **inclusive para `service_role` e para o
  dono da tabela**. É esta terceira camada que vale, porque as duas primeiras não alcançam quem
  conecta com a chave de serviço.

Consequência de agregação: `SUM(valor_centavos)` já está correto sem cláusula especial — o
estorno se cancela sozinho. Não existe estado "lançamento anulado"; existe um par que soma zero.

## Consequências

- **Somar é seguro por padrão.** Qualquer relatório novo, escrito por qualquer agente, acerta sem
  precisar lembrar de filtrar estornados. Esse é o argumento decisivo: o modelo errado só falha
  em código futuro que ninguém revisou.
- O `check` de sinal impede inserir valor negativo por acidente fora de estorno.
- Extrato do usuário mostra as duas linhas (original + estorno) — e **deve** mostrar: a UI
  precisa exibir a correção, não escondê-la. É a diferença entre auditoria e maquiagem.
- Lançamento em competência já fechada exige reabertura justificada e auditada (SPEC §5.4): o
  trigger de período fechado (`periodos_fechados`) vale também para o estorno.
- Erro de digitação trivial (um acento no histórico) também exige estorno + relançamento. Fricção
  aceita conscientemente: a alternativa é uma exceção "para casos simples", e toda exceção assim
  vira o caminho normal.
- A trilha em `audit.log` (ADR-0013) registra o INSERT do estorno com autor, motivo e timestamp,
  encadeado por hash. O par estorno+trilha é o que dá autoridade ao número publicado.

## Alternativas descartadas

- **(b) Tabela `estornos` separada.** Toda consulta financeira passaria a exigir `LEFT JOIN
  estornos` e um `WHERE ... IS NULL`, ou uma view que ninguém lembra de usar. O primeiro relatório
  escrito sem o join publica número errado, e o erro é silencioso. Descartado por isso.
- **(c) Versionamento bitemporal (`valid_from`/`valid_to`) com linha corrente.** Preserva
  histórico, mas o modelo mental vira "editar" com histórico anexo — o que contradiz a semântica
  contábil de estorno e, culturalmente, reabre a porta da correção discreta. Também complica toda
  consulta com predicado temporal.
- **Estorno com valor positivo + coluna `sinal` ou `tipo = 'estorno'`.** Devolve o problema do
  item (b): agregação exige lógica condicional, e quem esquecer soma o dobro.
- **`UPDATE` permitido enquanto o lançamento está em rascunho.** Tentador — mas cria dois regimes
  na mesma tabela e uma janela em que a regra não vale. Alternativa correta: a conferência do
  balancete (SPEC §5.1) acontece **fora** de `lancamentos`, numa área de staging da importação;
  a linha só nasce em `lancamentos` no momento da publicação, já imutável.
- **Soft delete (`deletado_em`).** Apagar sem apagar é o oposto da tese do produto.

## Status

Aceito.
