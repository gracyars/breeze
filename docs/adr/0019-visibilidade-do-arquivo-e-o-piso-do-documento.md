# ADR-0019 — A visibilidade do documento é o **piso**: override de página só amplia, nunca restringe

> Emenda ao ADR-0018 (D11). Fecha o achado **V3** do `auditor-rls`
> (`supabase/tests/01_visibilidade_documento_pagina_chunk_rls.sql`) e responde ao **V1**.

## Contexto

O ADR-0018 resolveu a granularidade **no índice** — `documento_paginas`, `chunks`, `deliberacoes`
passaram a ser filtrados por página. E esqueceu que **o objeto original continua monolítico**.

O `auditor-rls` provou o buraco com dois testes no mesmo cenário: documento `publico` com uma
página marcada `conselho`.

- **F1 (verde):** o texto da página restrita é corretamente negado em `documento_paginas` e
  `chunks`.
- **F2 (vermelho):** **o PDF com todas as páginas é baixável por anônimo**, porque a policy do
  bucket faz o gate por `app.documento_visivel` — nível do documento.

Ou seja: a restrição por página era ilusória. O texto ficava escondido na busca e o mesmo texto
saía inteiro pelo download. Pior que não ter a funcionalidade, porque dava sensação de controle.

### Correção de uma premissa, antes das opções

As opções levantadas foram (a) derivar `documentos.visibilidade` como o mínimo entre suas páginas,
(b) proibir override mais restritivo que o documento, (c) derivar duas representações do arquivo.

**(a) e (b) impõem exatamente a mesma invariante** — `documentos.visibilidade` no máximo tão
permissiva quanto a mais restritiva de suas páginas. Diferem só em *como*: (a) calcula e
sobrescreve; (b) declara e valida.

E o trade-off atribuído a (a) — "a ata com o Regimento embutido vira `autenticado` inteira,
e o regimento público volta para trás do login **no arquivo**" — **já é o estado atual, e vale
igualmente em (b)**. A ata AGE 04.02.2026 é `autenticado`; as páginas do regimento são `publico`.
`min(autenticado, publico) = autenticado`. Nada muda para esse documento em nenhuma das duas
opções. **A vitória da D11 nunca foi no arquivo — foi no texto, na busca e na citação.** O
regimento embutido continua público onde a pessoa efetivamente o lê, e o PDF de cartório continua
atrás de login, que é onde ele sempre esteve. Não há trade-off aqui a lamentar; havia um bug.

### O acervo real tem o caso inverso?

Conferido em `docs/inventario-acervo.md`, 43 documentos: **não hoje.** O caso que motivou a D11
(ata AGE de 36 páginas embutindo convenção, regimento, apólice e laudo) é override **mais
permissivo**. As cotações da pasta "Orçamentos Segurança" são `conselho` como arquivos inteiros,
não como página dentro de outro documento.

Casos plausíveis amanhã, e é bom nomeá-los: balancete `autenticado` cuja página de inadimplência
nominal deveria ser `conselho` (`condominio-documentos` §5); ata que nomeia unidades inadimplentes.
**A opção (b) atende esses casos** — só que forçando o arquivo a descer junto, que é a resposta
correta e não um beco sem saída. Ver "Quando o caso inverso aparecer", abaixo.

## Decisão

**(b), promovida a invariante verificável.**

### 1. Ordem total de permissividade — e a armadilha do nome

Para comparar níveis é preciso ordená-los. A ordem **não** é a que os nomes sugerem:

| Nível | Audiência | Ordem |
|---|---|---|
| `conselho` | gestão | 0 — **mais restritivo** |
| `restrito` | gestão ∪ moradores das unidades vinculadas | 1 |
| `autenticado` | qualquer pessoa autenticada | 2 |
| `publico` | todos, inclusive anônimo | 3 — mais permissivo |

`audiência(conselho) ⊆ audiência(restrito) ⊆ audiência(autenticado) ⊆ audiência(publico)`, porque
`restrito` **acrescenta** a unidade vinculada à gestão. **`restrito` é mais permissivo que
`conselho`, apesar do nome.** Inverter esses dois na implementação permitiria uma página
`conselho` dentro de um documento `restrito` — e o arquivo, baixável pelos moradores da unidade,
entregaria a página do conselho. É um leak de uma linha de código, num ponto onde o nome do enum
empurra ativamente para o erro.

```sql
create or replace function app.ordem_visibilidade(n public.visibilidade_documento)
returns int language sql immutable as $$
  select case n when 'conselho' then 0 when 'restrito' then 1
                when 'autenticado' then 2 when 'publico' then 3 end
$$;
```

### 2. A invariante

```
Para toda página p de um documento d:
    ordem(d.visibilidade)  <=  ordem(p.visibilidade)
```

`documentos.visibilidade` é o **piso**: o arquivo é no mínimo tão restrito quanto sua página mais
sensível. Override de página **só amplia** o alcance do texto derivado; nunca o reduz.

`<=` e não `=`: um documento mais restrito que todas as suas páginas é seguro (excesso de zelo) e
fica permitido. O que é proibido é o documento mais permissivo que qualquer página sua.

Garantida por trigger nas **duas** direções — validar só um lado deixa a porta aberta pelo outro:

- `documento_paginas` INSERT/UPDATE de `visibilidade`: rejeita override mais restritivo que o
  documento, com mensagem que diz o que fazer ("baixe `documentos.visibilidade` para `conselho`
  antes de marcar esta página").
- `documentos` UPDATE de `visibilidade`: rejeita afrouxar o documento acima de qualquer página já
  classificada.

### 3. `tem_paginas_mistas` passa a ser derivada (achado V1)

O V1 mostrou que a flag não era obrigatória quando havia override: o trigger de fronteira de chunk
não rodava e o chunk vazava pela busca, sem login. Uma flag que precisa ser marcada à mão para que
uma trava de segurança funcione **não é uma trava** — é uma convenção.

Duas mudanças:

1. **A flag deixa de ser autoral.** Trigger em `documento_paginas` a liga automaticamente quando
   surge o primeiro override; `documentos` não aceita desligá-la enquanto houver override.
   A `editor` ainda pode **ligá-la** antecipadamente para declarar "sei que é misto, ainda não
   classifiquei" — a flag é um limite inferior, nunca um valor livre:
   `tem_paginas_mistas >= exists(override)`.
2. **A trava de chunk deixa de depender dela para estar correta.** A verificação de fronteira roda
   sempre que existir override no intervalo do chunk. A flag vira apenas o índice que permite
   pular a checagem barata no caso comum, não a condição que decide se a segurança se aplica.

**E a semântica de "falha fechada" da D11 vira redundante** — consequência boa desta decisão que
merece ser dita. Sob a D11, página sem classificação em documento misto **não podia** herdar,
porque o padrão do documento podia ser mais permissivo que o conteúdo da página. Com a invariante
do item 2, o padrão do documento é o **piso**: herdar o piso é sempre seguro. A regra fail-closed
fica mantida por conservadorismo (custa nada, e protege contra um futuro em que a invariante seja
afrouxada), mas deixa de ser o que segura o modelo de pé.

### 4. O gate do bucket permanece em `app.documento_visivel`

E agora está **correto**, porque a invariante garante que o nível do documento é o do seu conteúdo
mais sensível. Nenhuma mudança de policy de storage é necessária — o que mudou foi a garantia por
trás dela. É a diferença entre a policy estar certa por acaso e estar certa por construção.

## Quando o caso inverso aparecer

Balancete `autenticado` com uma página de inadimplência nominal que precisa ser `conselho`. O
procedimento sob esta decisão:

1. `documentos.visibilidade` desce para `conselho` — o arquivo inteiro passa a ser só da gestão;
2. as demais páginas recebem override `autenticado`;
3. resultado: morador continua lendo, buscando e citando o corpo do balancete; **o PDF fica com a
   gestão**, porque o PDF de fato contém a página nominal.

Isso é o comportamento certo, não uma limitação. **Um PDF é atômico: quem o baixa leva tudo.**
O custo é real e precisa ser dito: o morador perde o "baixar o PDF original" nesse documento, e a
UI precisa explicar em vez de simplesmente esconder o botão — algo como "este arquivo contém dados
de outras unidades; o conteúdo público está disponível aqui". Se esse custo se mostrar alto na
prática, a saída **não** é afrouxar a invariante, é a opção (c): gerar um recorte derivado.

## Consequências

- **V3 fecha por construção**, não por vigilância. Não existe mais estado em que o texto é negado
  e o arquivo é liberado.
- **A curadoria fica mais explícita e mais chata:** classificar uma página sensível força uma
  decisão consciente sobre o arquivo inteiro, com erro alto e mensagem acionável. É o objetivo.
- **Ordem de operações importa na importação:** para um documento novo que já nasce misto,
  define-se primeiro o nível do documento (o piso), depois os overrides. O pipeline de F1 precisa
  seguir essa ordem, senão a primeira página classificada é rejeitada.
- **O caso que motivou a D11 continua funcionando sem nenhuma alteração de dado.**
- **Perda aceita:** um documento cuja maior parte é pública mas que tem uma página sensível fica
  com o arquivo restrito. Correto e honesto — ver acima.
- **Risco novo, pequeno:** `app.ordem_visibilidade` vira um segundo lugar onde a semântica dos
  níveis está codificada (o primeiro é `app.nivel_visivel`). Divergir os dois é possível. Contenção:
  teste pgTAP que afirma a ordem **contra a audiência real** — para cada par de níveis, prova que
  quem enxerga o mais restritivo é subconjunto de quem enxerga o mais permissivo. A ordem deixa de
  ser uma tabela que alguém digitou e passa a ser uma propriedade verificada.
- **Nomenclatura a rever com o `guardiao-dominio`:** `restrito` sendo mais permissivo que
  `conselho` é uma armadilha de leitura permanente, e não é do arquiteto renomear valor de domínio.
  Não altero agora — é enum, exige migração e é decisão de taxonomia.

## Alternativas descartadas

- **(a) Derivar `documentos.visibilidade` como `min()` das páginas.** Mesma invariante, mas
  aplicada por **efeito colateral silencioso**: classificar uma página rebaixa o documento sem que
  ninguém peça. Isso conflita com o trigger de `permite_publico` (ADR-0004), torna
  `documentos.visibilidade` não-declarativa — a `editor` define e o sistema sobrescreve — e
  esconde justamente a decisão que deveria ser consciente. Descartada pela forma, não pelo mérito.
- **(c) Duas representações — arquivo original restrito + recorte público servido pelo produto.**
  Resolve tudo e é o único caminho se o custo de UX de (b) se mostrar alto. Descartada **por ora**:
  cara, e o ADR-0018 já registrou que recorte de PDF quebra `sha256` como identidade do arquivo
  recebido e destrói a proveniência do documento de cartório — o recorte teria que ser
  explicitamente rotulado como derivado, com o original ainda referenciado. Fica registrada como a
  saída conhecida, não como não-solução.
- **Fazer o gate do bucket por página.** Impossível: o objeto no Storage é o PDF inteiro. Só faria
  sentido com (c).
- **Anteder `chunks` pela página mais restritiva do intervalo em vez de `pagina_ini`.** Mais
  robusto que a trava de fronteira, e descartado por custo: vira agregação por linha na tabela mais
  lida do produto. A trava de uniformidade entrega a mesma garantia com custo de escrita, não de
  leitura — e escrita aqui é rara (só o worker).
- **Manter `tem_paginas_mistas` autoral e cobrir com teste.** Foi exatamente o que o V1 derrubou:
  a flag não marcada desliga a trava em silêncio. Segurança que depende de alguém lembrar de marcar
  a caixinha não é segurança — o mesmo raciocínio da D12, aplicado a outro lugar.

## Status

**Corrigido pelo ADR-0023 em um ponto:** a regra fail-closed ("página sem classificação em
documento misto não herda") foi mantida aqui *por conservadorismo*, com a observação explícita de
que a invariante do piso já a tornava redundante. Essa camada redundante introduziu um predicado
não-local (`documento_tem_override`) que vazou na 3ª rodada. Lição incorporada: **redundância só é
defesa quando é local.** A invariante do piso, que é o núcleo deste ADR, permanece — e passa a ser
a única coisa que sustenta a herança.

Aceito, 2026-09-04. Emenda o ADR-0018 (que permanece Aceito; sua premissa de que a granularidade
por página bastava é corrigida aqui). Registrado em `docs/04-DECISOES.md` como D13.
Fecha V3 e V1 do veredito do `auditor-rls`; implementação com o `eng-supabase`.
