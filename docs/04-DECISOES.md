# Breeze — Registro de Decisões

Decisões travadas. Um agente que discordar deve levantar com o orquestrador, não contornar.

## 2026-09-04

**D1 — Importação assistida do balancete: aprovada.** Extração propõe, humano confere lado a
lado com o PDF, travas de consistência contábil bloqueiam publicação divergente. Ver SPEC §5.1.

**D2 — Autenticação por CPF ou e-mail.** Sempre resolve em magic link no e-mail cadastrado.
CPF é alias, nunca credencial. Ver SPEC §2.1. *Consequência:* a decisão pendente sobre acervo
público perde urgência — se todo morador tem conta, o acervo fica atrás de login e a camada
pública se restringe a convenção e regimento.

**D3 — O síndico é terceirizado e não tem acesso ao sistema.** Ele é o fiscalizado, não um
usuário. *Consequências:* (a) o risco de conflito político com síndico-administrador some;
(b) o sistema é operado inteiramente pelo lado fiscalizador; (c) nenhum fluxo pode depender de
ação do síndico dentro do produto — o dado dele entra pelo PDF que ele envia.

**D4 — Papel `editor` único.** Só a dona do projeto escreve, por ora; a subsíndica entra depois,
sem prazo. *Consequências:* (a) o gargalo de publicação é humano e único — a curadoria do acervo
precisa ser rápida ou o produto morre de backlog; (b) o papel `conselho` ganha importância como
contrapeso, com leitura completa e independente; (c) a trilha de auditoria continua obrigatória,
agora para dar credibilidade à própria editora perante os moradores.

**D5 — Skills que tocam OCR fiscal, contabilidade condominial ou dado pessoal são escritas
internamente.** Marketplace comunitário serve para descobrir ideia, não para instalar.

**D6 — Skills de terceiros instaladas** (aprovadas em 2026-09-04): `playwright-best-practices`
(currents-dev), `vitest` (antfu), `a11y-playwright-testing` (fugazi), `postgres-hybrid-text-search`
(timescale, **como referência de RRF apenas** — pressupõe `pg_textsearch`, indisponível no
Supabase gerenciado). Recusadas: `pdf-extraction` (Python contra worker Node, sem OCR, autor com
nome que imita fonte oficial) e toda opção de pgTAP (nada maduro; a única candidata tinha 1
instalação e nenhum assessment de segurança). **pgTAP para testes de RLS será skill interna** —
adicionar ao backlog do `auditor-rls`.

**D7 — Achados jurídicos que contrariam o senso comum do domínio**, todos verificados em fonte
primária pela skill `condominio-legal`. Registrados porque material desatualizado circula muito
neste domínio e um agente pode "corrigir" o produto para o errado:
- Art. 1.351 mudou em 2022 (Lei 14.405): mudança de destinação do edifício **não exige mais
  unanimidade**, são 2/3.
- Lei 8.212/91 art. 32, §11 **não diz mais "dez anos"** desde 2009.
- Art. 1.337, parágrafo único (comportamento antissocial) **não tem quórum na lei**; os 3/4
  aplicados por analogia são doutrina — marcado `[QUÓRUM CONTROVERSO]`.
- Exigir contas é direito coletivo, não individual (STJ REsp 2.050.372). Ver SPEC §6.4-bis.

**D8 — Arquitetura de F0 fechada em 16 ADRs, e correções aprovadas ao SPEC §2/§2.1.**
Os ADRs vivem em `docs/adr/` e são a fonte quando houver dúvida; o desenho do schema derivado
está em `docs/schema.md`. As sete decisões da tabela do SPEC §1.1 foram formalizadas sem mudança
de mérito. As demais, decididas agora:

- **Migração versionada com baseline única** (ADR-0008). Schema nunca é editado pelo dashboard,
  nem em staging. Migração é aditiva; não há `down` — rollback de schema com dado dentro é
  ficção. RLS entra na mesma migração que cria a tabela, nunca depois. Baseline é do `arquiteto`;
  toda migração posterior é do `eng-supabase`.
- **Ambientes** (ADR-0009). Dado de produção nunca é copiado cru para staging ou local — só dump
  anonimizado, gerado dentro de produção. Segredos por ambiente, sem interseção. Preview da
  Vercel aponta para staging.
- **Dinheiro é `bigint` em centavos, com sufixo `_centavos` obrigatório** (ADR-0010). O nome faz
  parte da decisão: `valor` sozinho não diz a unidade.
- **`lancamentos` imutável; estorno é lançamento na própria tabela, com self-FK e valor
  negativo** (ADR-0011). Assim `SUM()` sai correto sem filtro — o modelo alternativo só falharia
  em relatório futuro, em silêncio, que é o pior tipo de falha para este produto. Bloqueio de
  UPDATE/DELETE em três camadas, sendo a terceira um trigger que alcança `service_role`.
- **RLS é a fronteira única de autorização** (ADR-0012). Verificação em código de aplicação é
  ergonomia, nunca segurança. O espelhamento de `chunks`/`documento_paginas` é feito por **uma
  função** (`app.documento_visivel`) que todas as policies chamam — predicado copiado é
  literalmente a armadilha nº1 do SPEC §7, e diverge calado.
- **TOTP entra na autorização, não só na tela** (ADR-0003/0012). O helper de RLS só reconhece
  `editor`/`conselho` com `aal2`; sessão do conselho em AAL1 é tratada como `morador`.
  E **papel é dado, não claim de JWT**: mandato que vence hoje deixa de valer hoje.
- **Trilha em schema `audit` isolado, encadeada por hash** (ADR-0013), com advisory lock antes de
  ler o último hash (sem ele a cadeia bifurca sob concorrência) e redação de coluna sensível.
- **CPF: HMAC para lookup, cifra reversível — ambos na aplicação, chave fora do banco**
  (ADR-0014). Dump do banco não entrega CPF nenhum.
- **Enum nativo para conjunto fechado, tabela de domínio para conjunto operacional** (ADR-0015).
  `papel` tem três valores; `sindico_terceirizado` não entra — valor de enum é convite a criar
  conta (D3).

**Correções ao SPEC §2/§2.1 aprovadas e já aplicadas** (ADR-0016, itens 1 a 5 e 7 a 10):
âncora de citação estável `(documento_id, pagina) + trecho_literal` no lugar de
`deliberacoes.chunk_id`; `lancamentos.deliberacao_id` (sem ela o alerta crítico "fundo de reserva
sem ata" não era implementável); tabela `documento_unidades` (sem ela `visibilidade='restrito'`
não era avaliável); separação `audit.log` (permanente, encadeado) de `audit.acesso` (6 meses,
expurgável), porque cadeia de hash e retenção curta são incompatíveis; CPF em claro por rotina de
servidor com `REVOKE SELECT (cpf_enc)` no lugar de "via view", que era impossível com a chave fora
do banco; sufixo `_centavos` nas colunas monetárias que não o tinham; "escrita só admin" → `editor`
com AAL2; "quatro papéis" → três papéis de usuário; `unidades.numero` como texto.

*Consequências:* (a) o `eng-supabase` recebe um desenho fechado e materializa a baseline sem
decidir modelagem; (b) o `auditor-rls` tem alvo explícito — a matriz de RLS de `docs/schema.md`
§15 e os testes de negação listados por tabela; (c) duas pendências ficam com a dona do projeto e
**não bloqueiam F0**, porque o schema acomoda qualquer resposta sem migração destrutiva: quantos
`editor` no dia 1 e a recuperação de acesso se a editora única perder o TOTP (`papeis` já é N:N
com mandato; a contenção é operacional, não de schema), e a profundidade real do histórico num
condomínio recém-entregue (`tipos_alerta.requer_historico_meses` faz o motor não avaliar regra
sem base — regra de média móvel sem série produz falso positivo em série, e painel com falso
positivo vira ruído ignorado).

**D9 — Recuperação de acesso da editora única: códigos impressos.** A `editor` segue única. Gerar
8–10 códigos de recuperação de uso único, imprimir e guardar **fora de casa**. Sem segundo editor
e sem conta de quebra-vidro por ora. *Consequência:* a contenção é operacional, não técnica —
o `devops` deve incluir a geração e o teste de um código no runbook, e o teste trimestral de
restore deve verificar também que os códigos ainda funcionam. Perder o papel e o celular ao mesmo
tempo é perda total do acesso de escrita; o acervo continua legível pelos demais papéis.

**D10 — O condomínio foi entregue em dezembro de 2025.** Nove meses de operação em setembro/2026.
*Consequências, em ordem de impacto:*

1. **O caso de uso mais valioso do produto não é o que o SPEC descreve.** Num condomínio recém-
   entregue, o orçamento dos primeiros meses é de implantação, elaborado pela incorporadora, e a
   taxa condominial inicial é historicamente subestimada — o custo real só aparece quando o prédio
   entra em regime. Acompanhar o desvio entre o orçamento de implantação e o custo efetivo é
   exatamente o que um morador de prédio novo precisa e não tem. Isso deve ser tratado como
   funcionalidade de primeira classe em F2, não como consequência do orçado×realizado genérico.
2. **Alertas estatísticos:** série de 9 meses. Fracionamento (3 meses) já é válido; variação
   atípica (6 meses) passa a valer agora. Mantida a regra do ADR-0016: o motor compara contra a
   série realmente disponível e a UI diz "aguardando histórico" em vez de silenciar.
3. **Garantia e assistência técnica** são o tema de maior conflito num prédio de 9 meses, e estão
   fora do escopo atual. O acervo já contém manual do proprietário, formulário de assistência
   técnica e procedimentos de reforma. Avaliar para F2 — ver questão aberta abaixo.
4. **A convenção é a de instituição, da incorporadora**, provavelmente ainda não alterada em
   assembleia. O leitor de documentos precisa distinguir texto original de registro e alteração
   posterior deliberada — não é detalhe cosmético, é o que diz qual regra vale hoje.
5. Não há prestação de contas anual aprovada ainda. O primeiro exercício fecha em dez/2026.
