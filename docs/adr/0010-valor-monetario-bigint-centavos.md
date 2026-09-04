# ADR-0010 — Valor monetário em `bigint` de centavos, com sufixo `_centavos` obrigatório

## Contexto

O produto existe para que um número publicado bata com o documento que o comprova (Briefing §4.2,
SPEC §5.1). As travas de consistência contábil comparam somas com igualdade exata: soma das
contas = total do grupo; receitas − despesas = variação de saldo; saldo final = saldo inicial
seguinte. **Um centavo de divergência bloqueia a publicação** — e a trava só funciona se a
aritmética for exata. Com `float`, `0.1 + 0.2 <> 0.3`, e a trava passa a acusar erro onde não há
ou, pior, a mascarar erro real com tolerância de arredondamento.

Além disso o dado atravessa JSON (Server Actions, PostgREST). Em JavaScript, `number` é IEEE-754
de dupla precisão: `1234.56` não é representável exatamente.

## Decisão

1. **Toda quantia monetária é `bigint`, em centavos, inteira.** Nunca `float`, `real`, `double
   precision`, `money` ou `numeric` com escala decimal.
2. **A coluna carrega o sufixo `_centavos`.** `valor_centavos`, `valor_previsto_centavos`,
   `valor_mensal_centavos`, `valor_pago_centavos`, `limiar_cotacao_centavos`. O nome é parte da
   decisão: `valor` sozinho não diz a unidade, e o erro de unidade é invisível até virar 100× em
   um relatório.
3. **Conversão só nas bordas.** A aplicação recebe centavos, formata para exibição
   (`Intl.NumberFormat('pt-BR', {style:'currency', currency:'BRL'})`) e faz o caminho inverso na
   entrada. Nenhuma camada intermediária vê reais.
4. **`bigint` chega ao TypeScript como `string`** (o driver serializa `int8` como string para não
   perder precisão). O tipo gerado reflete isso. Aritmética no cliente usa `BigInt`, ou —
   preferencialmente — **não acontece**: soma é `SUM()` no Postgres.
5. **Percentual, fração ideal e índice de reajuste não são dinheiro** e continuam `numeric` com
   escala explícita. `fracao_ideal numeric(12,9)`, `confianca_ocr numeric(4,3)`.
6. Rateio que não divide exato (ex.: R$ 1.000,00 por 3 unidades) **precisa de regra de resíduo
   explícita** — a sobra de centavos vai para a maior fração ideal, e a soma das parcelas é
   verificada contra o total. Nunca arredondar cada parcela e torcer.

## Consequências

- Teto de `bigint`: ~92 quatrilhões de centavos. Irrelevante como limite, folgado por eternidades.
- `SUM(valor_centavos)` retorna `numeric` no Postgres (promoção automática para evitar overflow) —
  o código de aplicação precisa esperar isso, não `bigint`.
- Legibilidade em consulta ad-hoc é pior: `4320000` em vez de `43.200,00`. Mitigação: views de
  relatório expõem `valor_centavos / 100.0` **apenas para exibição**, com o nome deixando claro
  que é derivado, e jamais como base de nova agregação.
- Migrar depois seria caríssimo (toda coluna, todo índice, todo cálculo, toda verificação de
  histórico). É exatamente a classe de decisão que justifica um ADR: barata agora, irreversível
  em seis meses.

## Alternativas descartadas

- **`numeric(14,2)`.** Exato e correto aritmeticamente — descartado por dois motivos: atravessa
  JSON como string ou número dependendo do driver (ambiguidade de borda), e admite escala
  fracionária silenciosa em multiplicação (`numeric` de rateio gera `0.005`), reabrindo a porta
  do arredondamento implícito. Inteiro em centavos não tem estado intermediário fracionário.
- **`double precision` / `float`.** Erro de representação em dado financeiro. Não é opinião.
- **Tipo `money` do Postgres.** Depende de `lc_monetary` da sessão, tem precisão fixa herdada da
  configuração e é notoriamente desaconselhado.
- **`integer` (4 bytes) em centavos.** Teto de ~R$21 milhões. Suficiente hoje, e exatamente o
  tipo de aposta que envelhece mal em série histórica acumulada.

## Status

Aceito. Formaliza a regra do SPEC §2 ("valor monetário sempre `bigint` em centavos").
Ver ADR-0016 para as colunas do SPEC §2 hoje escritas sem o sufixo.
