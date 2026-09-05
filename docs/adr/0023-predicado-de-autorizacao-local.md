# ADR-0023 — Predicado de autorização não pode depender de linhas que não são a linha avaliada

> Terceiro ângulo da família do ADR-0021. Fecha o vazamento da 3ª rodada do `auditor-rls`.

## Contexto

`app.nivel_efetivo()` decide o nível de uma página assim:

```sql
case when app.documento_tem_override(d.id)   -- ← olha TODAS as páginas do documento
     then dp.visibilidade                    -- fail closed: NULL fica invisível
     else coalesce(dp.visibilidade, d.visibilidade)
end
```

`app.documento_tem_override()` é um `exists` sobre **outras linhas** de `documento_paginas`. Logo o
nível da página 5 depende do que existe na página 3.

O caminho que o auditor construiu: documento com piso `publico`, página 3 com override, páginas 5 e
6 sem classificação. Enquanto o override existe, 5 e 6 têm nível nulo e o `anon` lê vazio. **Apaga-se
a página 3** e `documento_tem_override` vira `false` — 5 e 6 passam a herdar `publico`.
**Conteúdo fechado abriu sozinho por causa de um `DELETE` em outra linha.**

E a anomalia é simétrica, o que é pior: sob a invariante do piso (ADR-0019), um override só pode ser
**mais permissivo** que o documento. Num documento `publico` — o nível máximo — o único override
possível é `publico`, isto é, **um no-op**. Marcar uma página com o mesmo nível do documento
**fecha todas as outras**. O predicado erra nas duas direções.

Estender o invalidador ao `DELETE` não resolve, e o auditor confirmou: `documento_paginas` vaza
direto, sem chunk envolvido. O invalidador cuida do derivado (`chunks`); aqui o defeito está no
predicado.

## Sobre a formulação — concordo com o diagnóstico, discordo do "única"

A formulação proposta foi:

> quando o valor de um predicado de autorização depende de linhas que não são a linha avaliada,
> toda escrita em qualquer daquelas linhas é uma mudança de autorização — e a única forma barata de
> domar isso é fazer o predicado **monotônico** (só aperta, nunca afrouxa).

**A primeira metade está certa e é a frase que fica.** É definicional e ninguém a estava usando:
`exists(...)` dentro de um predicado de RLS transforma escrita em linha alheia em concessão ou
revogação de acesso, sem que ninguém escreva "grant" em lugar nenhum.

**A segunda metade não sobrevive ao resto do schema**, e a diferença importa porque a versão
literal é perigosa. Duas objeções:

### Objeção 1 — monotonicidade é errada para a não-localidade *constitutiva*

Nem toda dependência não-local é acidente. Há duas espécies:

| Espécie | As outras linhas… | Exemplos | Escrita nelas é… |
|---|---|---|---|
| **Constitutiva** | **são** a decisão de autorização | `papeis`, `vinculos`, `documento_unidades` | …exatamente o que se quer: conceder e **revogar** |
| **Modal / incidental** | só decidem **como** a regra se aplica, não quem vê | `documento_tem_override` | …uma mudança de autorização que ninguém percebeu ter feito |

Se "torne o predicado monotônico" virar regra geral, alguém aplica em `app.tem_papel()` — e
monotônico ali significa **mandato que nunca expira**. Isso contraria frontalmente o veto do
`juridico-lgpd`: o acesso cessa em `vinculos.fim` **+ 0 dias**. Revogação *precisa* afrouxar.
A monotonicidade serve à espécie **modal**, onde a não-localidade nunca foi uma decisão de
negócio — e é justamente por não ser percebida como decisão que ela vaza.

### Objeção 2 — havia uma saída mais barata, e ela estava escrita no ADR-0021

O nível 0 da hierarquia é **eliminar**: remodelar para a invariante não existir. Aqui a eliminação
está disponível e é mais simples que o patch — basta remover o ramo:

```sql
-- nivel_efetivo, versão local:
select coalesce(dp.visibilidade, d.visibilidade) ...
```

Isso lê **apenas** a linha avaliada e o documento dela. Sem `exists`, sem "misto", sem flag.

**E o ramo removido não protegia nada.** O próprio comentário da migração admite: *"com o piso
garantido por trigger, todo override é ≥ `documentos.visibilidade` — herdar o piso do documento
para a página sem override é seguro por construção"*. Com a invariante do piso (ADR-0019) valendo,
o piso **é** o nível mais restritivo do documento; herdá-lo é o comportamento correto. O ramo
fail-closed protegia contra um cenário que a invariante do piso já tornou impossível — e, em troca,
introduziu a não-localidade que vazou.

Foi um erro meu, e é preciso nomeá-lo porque é reutilizável: **no ADR-0019 eu registrei que a
regra fail-closed tinha virado redundante e a mantive "por conservadorismo".** Defesa em
profundidade não é gratuita. Uma camada redundante que introduz dependência não-local não é
proteção extra: é superfície extra. **Redundância só é defesa quando é local.**

## Decisão

### 1. O princípio, na forma que fica

> **Predicado de autorização deve ser local:** seu valor pode depender da linha avaliada, das
> linhas que a definem por chave estrangeira, e do sujeito da sessão — de mais nada.
>
> Quando o valor depende de outras linhas, **toda escrita naquelas linhas é uma mudança de
> autorização**, ainda que ninguém a tenha chamado assim.

Ordem de tratamento, quando a não-localidade aparecer:

**Nível 0 — Tornar local.** Sempre a primeira pergunta. Frequentemente a não-localidade é uma
inferência (`exists(...)`) que substitui um fato que poderia estar na própria linha.

**Nível 1 — Se for constitutiva, mantê-la e guardá-la.** `papeis` e `vinculos` são não-locais de
propósito. O tratamento não é monotonizar — é reconhecer que escrita ali é ato de autorização:
guarda em toda operação, auditoria, e teste de **revogação** (o caminho que afrouxa é o que
precisa funcionar).

**Nível 2 — Se for modal e não der para eliminar, monotonizar.** Fazer o predicado só apertar,
nunca afrouxar (ex.: sinalizador que liga e nunca desliga, em `OR` com o derivado). É o patch que
o `eng-supabase` verificou fechar. Vale como degrau, não como objetivo.

**Nunca:** monotonizar um predicado constitutivo. Quebra revogação, que é obrigação legal aqui.

### 2. O conserto

**Remover o ramo `documento_tem_override` de `app.nivel_efetivo()`**, tornando o predicado local, e
remover a função. `documentos.tem_paginas_mistas` permanece apenas como o que já é desde a D13 —
sinalizador de intenção da curadoria para a UI — e **deixa de participar de qualquer decisão de
segurança**, inclusive por `OR`.

A trava de fronteira de chunk (`chunks_valida_visibilidade_uniforme`) **continua** e passa a rodar
sempre que houver override no intervalo, sem consultar o "misto". Ela é uma validação de escrita,
não um predicado de leitura — a distinção é o ponto deste ADR.

*Se o patch monotônico já estiver aplicado*, ele fecha o vazamento e não precisa ser revertido às
pressas; mas o alvo é a remoção, porque manter o ramo preserva a anomalia inversa (override no-op
fechando páginas que deveriam estar abertas) — respostas erradas monotônicas continuam sendo
respostas erradas.

### 3. Reavaliação do nível 0 do ADR-0019 — pedido explicitamente, feito

*Calcular a visibilidade do chunk como o **mínimo** sobre seu intervalo de páginas, em leitura, em
vez de manter a invariante de uniformidade.* Revisto à luz deste ADR: **continua descartado, e
agora por um motivo melhor.** Não é só custo — `min()` sobre outras linhas é exatamente um
predicado não-local, da espécie modal. Trocaria a invariante de uniformidade por uma dependência
que este ADR proíbe. A uniformidade validada na escrita, com invalidação no segundo caminho
(ADR-0021), mantém o predicado de leitura **local ao chunk**. Registrado para não ser
redescoberto pela terceira vez.

## Consequências

- Um predicado a menos, uma função a menos, uma coluna fora do caminho de segurança. O modelo de
  visibilidade fica menor do que era antes do bug.
- **`app.nivel_efetivo` passa a depender criticamente da invariante do piso.** Se o piso for
  violado, a herança fica insegura. Isso é aceitável e é *melhor* que a alternativa: a dependência
  vira **uma** invariante nomeada, testada e com matriz de caminhos (ADR-0021), em vez de um ramo
  defensivo que ninguém sabia enumerar. Dependência explícita e testada > defesa implícita.
- Regra de revisão que decorre: **`exists`, `count`, `min`, `max` ou qualquer agregação dentro de
  uma função chamada por policy é sinal de alerta.** Não é proibido — `nivel_visivel` usa `exists`
  sobre `documento_unidades`, que é constitutivo — mas exige classificar a espécie e justificar.
- Correção de rumo sobre a D13: **"sempre derivar" era conselho incompleto.** Derivar não elimina a
  dependência, **muda o dono dela** — de um humano que esquece para outras linhas que mudam. Derivar
  só ganha quando a fonte é a própria linha avaliada, ou quando é constitutiva e guardada. A flag
  autoral do V1 era ruim por ser autoral; o derivado que a substituiu era ruim por ser não-local.
  A resposta certa não era nenhuma das duas: era não precisar do conceito.

## Alternativas descartadas

- **Estender o invalidador ao `DELETE` de página.** Verificado pelo auditor: não fecha.
  `documento_paginas` vaza direto, sem chunk no caminho. Trata o derivado, não o predicado.
- **Monotonizar e parar por aí.** Fecha o vazamento e preserva a anomalia inversa. Degrau, não alvo.
- **Proibir `DELETE` em `documento_paginas`.** Fecha um caminho de um predicado que não deveria
  existir. Além disso reprocessamento apaga e recria páginas por desenho (SPEC §3).
- **Materializar `visibilidade` obrigatória em toda página, sem `NULL`.** Também torna o predicado
  local e é elegante. Descartada por ora por ser mudança de dado (backfill de todas as páginas) para
  o mesmo efeito que `coalesce` já entrega de graça sob a invariante do piso. Fica registrada como
  a evolução natural se o `NULL` de herança causar confusão na curadoria.

## Status

Aceito, 2026-09-04. Terceiro ângulo do ADR-0021; corrige por conservadorismo excessivo o ADR-0019 e
o ADR-0018. Registrado em `docs/04-DECISOES.md` como D16. Artefato de verificação:
`docs/invariantes/`.
