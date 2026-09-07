# Parecer — Off-boarding de ex-morador e a derivação de `app.eh_autenticado()`

**Origem:** achado do `auditor-rls`. `app.eh_autenticado()` = existe `pessoas` com `ativa = true`.
`papeis` e `vinculos` têm mandato datado e expiram sozinhos; `ativa` não expira.
**Efeito:** quem vendeu a unidade segue lendo todo documento `autenticado` — atas com nome, voto e
unidade, balancetes, contratos — até alguém rodar um UPDATE que não está modelado em lugar nenhum.

**Veredito: VETADO PARCIAL — aprovado com condição.**
Vetada a ida a produção de `app.eh_autenticado()` na forma atual (condições C1–C3 abaixo).
Aprovado o resto do desenho de off-boarding como backlog datado, sem bloqueio de F0.

**Retenção fixada (SPEC §7):** acesso cessa em `vinculos.fim` + 0 dias — **zero tolerância depois
do fato**, hoje com resolução de instante (ADR-0030); o que a ponta `fim` significa quando a saída é
planejada está no parecer `pareceres/2026-09-06-default-da-tela-encerramento-de-vinculo.md`. PII cadastral do
ex-morador: **5 anos** após `fim` (Lei 4.591/64, art. 22, §1º, "g"), depois anonimização.
Lançamento, cobrança, ata, deliberação e parecer do período: inalterados (LGPD art. 16, I).

---

## 1. Quanto tempo o ex-condômino pode acessar o acervo

**Direito dele.** Inspecionar documentos da administração é direito **individual do condômino**.
É direito *da condição*, não da pessoa: extinta a condição, extingue-se o direito. Sobrevivem, e não
como sessão aberta:

> **Correção de citação, 2026-09-06 (`juridico-lgpd`, com fonte primária em mãos).** A redação
> anterior atribuía esse direito ao **CC art. 1.335**. O texto vigente do art. 1.335 traz três
> incisos — usar/fruir/dispor da unidade, usar as partes comuns, e *votar nas deliberações da
> assembleia e delas participar, estando quite* — e **nenhum** deles menciona inspeção de documentos.
> O fundamento textual correto é o **art. 1.348, VIII** (compete ao síndico "prestar contas à
> assembleia, anualmente e quando exigidas") combinado com o **art. 1.335, III** (participar da
> assembleia é direito de quem é condômino) e com a **Lei 4.591/64, art. 22, §1º, "g"**. O caráter
> *individual* — fiscalizar fora da assembleia — é **jurisprudencial**, não textual;
> `REsp 2.050.372` segue citado e **não foi verificado nesta sessão** (Planalto não publica acórdão
> do STJ). A conclusão do parecer não muda: o direito continua sendo *da condição*, e o art. 1.335,
> III o diz com todas as letras.


- **Cópia do próprio período**, mediante pedido (LGPD art. 18, II). Atendida pela `editor` por
  export, com registro em `audit.acesso`.
- **Documento necessário à defesa em processo** (LGPD art. 7º, VI). Base para a *entrega mediante
  pedido fundamentado*, nunca para leitura contínua e indiscriminada.
- **Prova de quitação do período.** Interesse real: o adquirente responde por débito do alienante
  (obrigação *propter rem*) e a cobrança prescreve em ~5 anos
  `[NÃO CONFIRMADO — CC art. 1.345 e art. 206, §5º, I; ver "Pendência de verificação" ao final]`.
  É o que justifica **guardar** o cadastro por 5 anos, não o que justifica dar-lhe login.

**Excesso, sem base legal nenhuma.** Ata do mês passado, balancete corrente, inadimplência
agregada atual, contrato assinado depois da saída. A prestação de contas destina-se à **assembleia
de condôminos** (CC art. 1.348, VIII; art. 1.350) — ele não a integra mais. Manter o acesso viola
necessidade (LGPD art. 6º, III) e o art. 15, I: alcançada a finalidade, o tratamento termina.

## 2. Gatilho correto

**`vinculos.fim`, e só ele.** Não "venda", não "fim de locação", não inatividade — todos são
*motivos* de um mesmo fato datado que a `editor` **já precisa** registrar para parar de emitir
cobrança. Inatividade é gatilho errado: não distingue quem saiu de quem só não entra no sistema.

**Quem executa: ninguém.** É a única resposta robusta com editora única (D4) que pode esquecer.
A desativação deve ser **derivada** do fato, não um segundo passo humano. O que continua humano é
registrar a venda — e isso o produto pode tornar *visível quando falta* (§5), não pode adivinhar.

## 3. Cessar de uma vez ou degradar

**Cessa de uma vez.** Recomendo **não** construir janela de acesso degradado em F0.

- **Defensável e obrigatório:** perda imediata de `autenticado`; direito a cópia sob pedido.
- **Só conveniente:** janela de 90 dias lendo o próprio histórico. Reduz atrito com a editora
  única, mas cria uma **quarta classe de visibilidade** e um predicado novo de RLS
  (`documentos.data_documento <= vinculos.fim` cruzado com unidade) — superfície de auditoria nova
  para servir um caso que ainda não ocorreu. Custo/risco desfavorável. Se um dia entrar, entra como
  nível próprio, jamais como sobra de `eh_autenticado()`.

## 4. O rastro

| Rastro | Destino | Fundamento |
|---|---|---|
| `pessoas.nome`, `email`, `telefone`, `cpf_hash`, `cpf_enc`, `cpf_ultimos_digitos` | Anonimizar em `fim + 5 anos`; `auth_user_id` → null | LGPD art. 12 e 16, I |
| `pessoa_id` | Preservar sempre | Chave técnica dos agregados |
| `questionamentos` (autor) | Autoria acompanha `pessoas`; **texto permanece** | Valor fiscalizatório |
| `pareceres` / `parecer_signatarios` se foi conselheiro | **Não anonimizar, nunca** | Assinatura é a validade do parecer (CC art. 1.356); art. 16, I |
| Nome em ata, deliberação, voto | Permanece | Registro da assembleia; art. 16, I |
| `lancamentos`, `cobrancas` do período | Permanecem íntegros | Prestação de contas; ADR-0011 |
| `audit.log` | **Não tocar** — cadeia de hash | Redação retroativa quebra a cadeia |

`audit.log` só fica coberto se `actor` for **id**, nunca nome denormalizado — anonimizar `pessoas`
de-identifica a trilha por consequência. **Verificar; se houver nome copiado, é achado novo.**

**Correção à skill `lgpd-condominio` — feita.** A §6 mandava anonimizar *ao encerrar o vínculo*.
Cedo demais: destrói a capacidade de cobrar débito remanescente, de responder pedido do titular e
de provar quitação dentro dos 5 anos de guarda. A skill agora traz a §6-bis com o modelo de dois
estágios, a lista fechada do que nunca se anonimiza e o item 10 do checklist ("o acesso a esse
dado expira sozinho?").

## 5. Modelo pedido (regra; migração é do `eng-supabase`)

1. `app.eh_autenticado()` = `pessoa ativa` **E** (vínculo vigente **OU** papel vigente).
   `ativa` vira kill-switch administrativo, nunca o portão sozinho.
2. **Armadilha:** editora e conselheiros sem vínculo vigente se auto-trancam. Por isso o `OU papel
   vigente` — e o `auditor-rls` testa esse caso antes de tudo (interage com D9).
3. `vinculos.motivo_fim` (enum: `venda`, `fim_locacao`, `obito`, `pedido_titular`,
   `erro_cadastral`) e `pessoas.anonimizada_em`, para tornar o estado explícito e a rotina idempotente.
4. Rotina semanal — alerta, não UPDATE silencioso: `unidade_sem_vinculo_vigente` e
   `pessoa_ativa_sem_vinculo_e_sem_papel`. Nenhum schema detecta venda não informada; o máximo
   honesto é tornar a inconsistência visível.
5. Rotina de anonimização (`fim + 5 anos`, sem outro vínculo/papel), com lista de dry-run à
   `editor`. Só dispara em 2031 (D10) — **testar com data falsa, não esperar**.

---

## Condições que bloqueiam produção

- **C1.** `app.eh_autenticado()` derivada de vínculo/papel vigente. `ativa` deixa de ser portão único.
- **C2.** Teste de negação no `auditor-rls`: pessoa com `ativa = true` e `vinculos.fim` no passado,
  sem papel, lendo documento `autenticado` → 0 linhas. Mais o teste positivo do item 5.2.
- **C3.** Procedimento de saída escrito no runbook: registrar `fim` e `motivo_fim` no mesmo ato em
  que se para a cobrança.

Não bloqueiam F0: `motivo_fim`, alertas, rotina de anonimização, janela degradada (recusada).

## Pendência de verificação — **fechada em 2026-09-06, com ressalva**

A sessão original do `juridico-lgpd` não tinha `Bash` e não conseguiu confirmar as duas citações.
Esta sessão tem, e baixou o Código Civil compilado do Planalto
(`ccivil_03/leis/2002/l10406compilada.htm`). Resultado:

| A verificar | Situação | Texto vigente |
|---|---|---|
| **CC art. 1.345** | **CONFIRMADO**, literal | "O adquirente de unidade responde pelos débitos do alienante, em relação ao condomínio, **inclusive multas e juros moratórios**." |
| **CC art. 206, §5º, I** | **CONFIRMADO**, literal | "Em cinco anos: I - a pretensão de cobrança de **dívidas líquidas constantes de instrumento público ou particular**." |
| **CC art. 1.245** *(verificado de passagem)* | **CONFIRMADO** | "Transfere-se entre vivos a propriedade mediante o **registro do título** translativo no Registro de Imóveis." — sustenta que a venda é fato **datado**, e é o eixo do parecer sobre o default da tela. |
| **CC art. 1.348, VIII** | **CONFIRMADO** | "Compete ao síndico: [...] VIII - **prestar contas à assembleia, anualmente e quando exigidas**." |

**Ressalva que permanece `[NÃO CONFIRMADO]`, e é a que importa:** o texto do art. 206, §5º, I fala em
*dívida líquida constante de instrumento público ou particular*. Que a **cota condominial** se
enquadre nessa hipótese é ponte **jurisprudencial**, não textual — não está no Planalto e não foi
verificada aqui. O prazo de guarda de **5 anos** não depende dela: apoia-se na **Lei 4.591/64,
art. 22, §1º, "g"**, já verificada. A ponte serve de reforço, não de alicerce; **não citar precedente
do STJ sem verificar o acórdão.**

Levar as duas linhas confirmadas para a `condominio-legal` §4 (tabela de prazos de guarda) — fora do
escopo de arquivo deste agente nesta sessão.

## Checklist acionável

- [x] `juridico-lgpd`: corrigir skill `lgpd-condominio` (§6-bis, dois estágios, exceções, item 10)
- [ ] `eng-supabase`: reescrever `app.eh_autenticado()` (C1) — **antes de produção** *(→ V8)*
- [ ] `auditor-rls`: testes C2, negativo e positivo — **antes de produção**
- [ ] `auditor-rls`: confirmar que `audit.log.actor` é id, não nome — **antes de produção**
- [ ] `devops`: C3 no runbook — **antes de produção**
- [ ] `eng-supabase`: `vinculos.motivo_fim`, `pessoas.anonimizada_em` — F1
- [ ] `eng-supabase`: dois `tipos_alerta` do item 5.4 — F1
- [ ] `eng-supabase`: rotina de anonimização + teste com data falsa — F1
- [x] confirmar CC art. 1.345 e art. 206, §5º, I — **feito em 2026-09-06**, fonte primária; a
      ponte "cota condominial = dívida líquida" segue jurisprudencial e não verificada
- [ ] `arquiteto`: ADR-0030 §3 — trocar a escolha da editora pela derivação por `motivo_fim`
      (parecer `pareceres/2026-09-06-default-da-tela-encerramento-de-vinculo.md`)
- [ ] `juridico-lgpd`: levar CC art. 1.345 e 206, §5º, I para `condominio-legal` §4 — F1
