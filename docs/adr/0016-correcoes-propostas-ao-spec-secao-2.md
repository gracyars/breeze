# ADR-0016 — Correções propostas ao SPEC §2 e §2.1

## Contexto

Ao desenhar o schema (`docs/schema.md`) a partir do SPEC §1, §2, §2.1, §3, §4, §5 e §7,
apareceram **contradições internas e lacunas** que impedem materializar o modelo sem escolher
por conta própria. O arquiteto não altera o SPEC unilateralmente (escopo fechado). Este ADR
registra cada ponto, a resolução adotada no desenho, e escala a decisão de texto ao orquestrador.

Todos os itens estão **implementados em `schema.md` na forma descrita abaixo**, e sinalizados lá.

> **Resultado:** o orquestrador aprovou os dez itens em 2026-09-04 e autorizou, uma única vez, a
> escrita no SPEC. As correções já estão aplicadas em `docs/01-SPEC.md` (§1.1, §2, §2.1, §5.3,
> §5.4, §7) e registradas em `docs/04-DECISOES.md` como D8. O texto abaixo é mantido como está —
> ADR aceito não se reescreve — com a marcação de aceite e as pendências no fim.

## Itens

### 1. `deliberacoes.chunk_id` é âncora instável — **contradição real**
SPEC §2 ancora a citação de deliberação em `chunk_id`. Mas SPEC §3 exige pipeline idempotente e
"reprocessar tudo deve ser um comando": reprocessar regenera `chunks` com outra segmentação, e a
citação da deliberação aponta para nada ou, pior, para outro trecho.
**Proposta:** a âncora estável passa a ser `documento_id` + `pagina` + `trecho_literal`
(snapshot do texto citado). `chunk_id` permanece como ponteiro **fraco**
(`on delete set null`), reconstruível por busca do trecho. Vale para `deliberacoes` e para
qualquer citação persistida.

### 2. Colunas monetárias sem o sufixo `_centavos` — **inconsistência**
SPEC §2 fixa "valor monetário sempre `bigint` em centavos" e, na mesma tabela, nomeia
`cobrancas.valor`, `cobrancas.valor_pago`, `contratos.valor_mensal`,
`orcamento.valor_previsto`, sem sufixo.
**Proposta:** renomear no SPEC para `valor_centavos`, `valor_pago_centavos`,
`valor_mensal_centavos`, `valor_previsto_centavos` (ADR-0010, item 2).

### 3. `papeis` "escrita só admin" — **papel inexistente**
Não existe papel `admin` no modelo. Os papéis são `editor`, `conselho`, `morador` (§2.1, D4).
**Proposta:** trocar por "escrita só `editor`, com AAL2". Nota de risco registrada: com D4
(`editor` única), quem concede papel é quem detém todos — a trilha (ADR-0013) é a única
contenção. Isso reforça o Briefing §7 item 2 (quem mais será administrador no dia 1) como
decisão pendente **de F0**, não de depois.

### 4. "Quatro papéis" vs. três valores de enum — **ambiguidade perigosa**
§2.1 diz "quatro papéis" e lista `sindico_terceirizado` na mesma tabela dos demais, embora o
texto diga que ele não é conta (D3).
**Proposta:** o texto passa a dizer "três papéis de usuário; o síndico terceirizado é entidade
referenciada, não papel". `sindico_terceirizado` **não existe** no enum `papel` (ADR-0015);
existe como `fornecedores.eh_sindico_terceirizado`.

### 5. "CPF em claro só para `editor`, via view" — **impossível como escrito**
Com a chave de cifra fora do banco (ADR-0014, exigido pelo próprio §2.1), **nenhuma view SQL
consegue decifrar**. E RLS não filtra coluna.
**Proposta:** trocar por "CPF em claro só para `editor`, decifrado em rotina de servidor após
checagem de papel e registro em `audit.acesso`; `cpf_enc` sem `SELECT` para `authenticated`".

### 6. `lancamentos` sem `deliberacao_id` — **lacuna**
O alerta crítico "Fundo de reserva sem ata" (§5.3) e a regra de fundo da skill
`condominio-plano-de-contas` §4 exigem vincular o débito em fundo à deliberação que o autorizou.
A coluna não está listada em §2.
**Proposta:** acrescentar `lancamentos.deliberacao_id` (nullable, FK para `deliberacoes`).

### 7. Visibilidade `restrito` sem vínculo a unidade — **lacuna**
`documentos.visibilidade = 'restrito'` existe para notificações e multas, visíveis "só à unidade
notificada" (skill `condominio-documentos` §11). Não há como avaliar isso: nada liga documento a
unidade.
**Proposta:** nova tabela associativa `documento_unidades (documento_id, unidade_id)`.
Sem ela, `restrito` não é implementável e vira sinônimo de `conselho`.

### 8. Tabelas citadas fora do §2 — **lacuna de inventário**
Aparecem no texto do SPEC mas não na tabela do modelo de dados: `sinonimos` (§4),
tabela de limiares/configuração (§5.3), fila de processamento (§1.1 ADR-7), fechamento de período
(§5.4), parecer versionado do conselho (§5.4), tipos de documento (taxonomia).
**Proposta:** acrescentar ao §2 — `sinonimos`, `configuracoes`, `job.fila`, `periodos_fechados`,
`pareceres` + `parecer_signatarios`, `tipos_documento`, `tipos_alerta`,
`fornecedor_dados_bancarios` (necessária ao alerta crítico "troca de dados bancários", §5.3).

### 9. Log de acesso com retenção de 6 meses dentro de trilha imutável — **contradição**
§7 pede retenção de 6 meses para o log de acesso e trilha imutável encadeada. Expurgo quebra
cadeia de hash.
**Proposta:** duas tabelas — `audit.log` (mutação, encadeada, permanente) e `audit.acesso`
(leitura sensível, sem cadeia, expurgável em 6 meses). Ver ADR-0013.

### 10. `unidades.numero` como texto — **detalhe que trava depois**
`101-A`, `Cob 02`, `Loja 1` são reais. Numérico obriga a conversão perdida depois.
**Proposta:** `numero text`, com ordenação natural resolvida por coluna auxiliar de ordenação,
não por `cast`.

## Detalhamento do item 1 — por que âncora inline, e não tabela `citacoes`

O orquestrador pediu a escolha explícita da representação estável. Duas eram viáveis:

- **(A) âncora inline em `deliberacoes`:** `documento_id`, `pagina`, `trecho_literal`, mais
  `chunk_id` como ponteiro fraco `on delete set null`.
- **(B) tabela `citacoes` com id próprio**, referenciada por `deliberacoes` e por qualquer outra
  entidade que venha a citar.

**Escolhida: (A).** Razão: `lancamentos` **já** ancora sua fonte inline (`documento_id`,
`pagina_origem`), por exigência do SPEC §5.1.4. Adotar (B) criaria dois padrões diferentes de
citação convivendo no mesmo schema — e padrão duplicado é o que faz um agente futuro escolher o
errado. (B) também adiciona uma indireção para o que hoje é um relacionamento 1:1.

O custo de (A) é assumido e é pequeno: se um dia várias entidades precisarem citar o mesmo trecho
(parecer citando ata, questionamento citando balancete), extrair a tabela `citacoes` é migração
**aditiva** — cria a tabela, popula a partir das colunas existentes, e as colunas antigas saem em
migração posterior (ADR-0008, item 4). Nada se perde por começar inline.

`trecho_literal` é o que sustenta a garantia: mesmo que documento e página mudem de numeração num
reprocessamento, o texto citado permanece verificável e re-localizável por busca.

## Itens aceitos e itens que seguem abertos

**Aceitos e aplicados** (orquestrador, 2026-09-04 — registrado em `docs/04-DECISOES.md` D8):
itens **1, 2, 3, 4, 5, 6, 7, 8, 9 e 10**. `docs/01-SPEC.md` §1.1, §2, §2.1, §5.3, §5.4 e §7 foram
atualizados; `docs/schema.md` reflete tudo.

**Abertos — decisão da dona do projeto, já encaminhada, não bloqueiam F0:**

- **(a) Quantos `editor` no dia 1, e recuperação de acesso se a `editor` única perder o TOTP.**
  Levantado no item 3 deste ADR (Briefing §7 item 2). O schema não muda com a resposta: `papeis`
  é N:N com mandato datado, então um segundo `editor` é um `INSERT` e revogar é preencher
  `mandato_fim`. O que **não** é resolvível por schema: com uma editora só, perder o segundo
  fator não tem recuperação por outro editor. A contenção é operacional — código de recuperação
  impresso, guardado fora do sistema, mais runbook (ADR-0003, ADR-0009). `[PENDENTE]`
- **(b) Profundidade real do histórico — o condomínio parece recém-entregue.** Afeta as regras de
  alerta que dependem de série: "variação atípica" (média móvel de 6 meses) e "fracionamento
  suspeito". Acomodado sem migração destrutiva por `tipos_alerta.requer_historico_meses` e pelas
  chaves `configuracoes.condominio_data_instalacao` / `competencia_mais_antiga`: o motor não
  avalia a regra enquanto a série disponível não alcança o mínimo, e a UI mostra "aguardando
  histórico" em vez de silenciar. Regra de média móvel sem base produz falso positivo em série, e
  painel de alerta com falso positivo vira ruído ignorado — que é como este diferencial morre.
  Relacionado ao Briefing §7 item 4 (profundidade do acervo a digitalizar). `[PENDENTE]`

## Consequências

- Itens 1, 6, 7, 8 e 9 eram **bloqueantes para a baseline**: sem eles, alertas críticos e a
  visibilidade `restrito` não são implementáveis, e a citação de deliberação quebraria no primeiro
  reprocessamento. Resolvidos.
- Itens 2, 3, 4, 5 e 10 eram correções de texto e nomenclatura, feitas antes de haver dado.
- O SPEC deixa de se contradizer entre §2 e §3 (âncora de citação) e entre §2 e §7 (CPF por view,
  retenção do log de acesso).
- As duas pendências acima ficam registradas **no ADR**, não só numa conversa: um agente que
  implementar o motor de alertas em F3 precisa encontrá-las sem perguntar.

## Alternativas descartadas

- **Alterar o SPEC sem aprovação.** Fora do escopo do arquiteto. A alteração só foi feita depois
  de autorização explícita do orquestrador, e é pontual.
- **Materializar o schema como o SPEC estava escrito.** Produziria uma baseline que não sustenta
  §5.3 nem §7, e a correção depois custaria migração com dado dentro.
- **Adiar as tabelas do item 8 para as fases em que são usadas.** Vale para as puramente de F2/F3,
  e é o que `schema.md` faz (marcação de fase por tabela). Não vale para `documento_unidades`,
  `tipos_documento` e `configuracoes`, que F0/F1 já precisam.
- **(B) tabela `citacoes`** — ver detalhamento do item 1 acima.
- **Bloquear F0 até as pendências (a) e (b) serem respondidas.** Desnecessário: nenhuma das duas
  altera o schema, e ambas foram desenhadas para caber por dado, não por migração.

## Status

**Aceito** em 2026-09-04. Itens 1–10 aprovados e aplicados em `docs/01-SPEC.md`,
`docs/schema.md` e `docs/04-DECISOES.md` (D8). Pendências (a) e (b) seguem abertas com a dona do
projeto e estão registradas acima — não bloqueiam a materialização da baseline.
