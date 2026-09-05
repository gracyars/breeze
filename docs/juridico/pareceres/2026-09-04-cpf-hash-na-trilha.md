# Parecer — `cpf_hash` é pseudonimização, não anonimização (escopo do V9)

**Pergunta (via `auditor-rls`):** `cpf_hash` é HMAC-SHA256 com pepper fora do banco e sobrevive em
claro dentro de `audit.log`. É dado anonimizado — e portanto fora da LGPD, art. 12 — ou é
pseudônimo, e portanto dado pessoal?

**Veredito: PSEUDONIMIZAÇÃO. `cpf_hash` é dado pessoal.**
**Condição bloqueante:** o V9 deve redigir `cpf_hash` **junto com** `cpf_enc` em `antes`/`depois`.

**Retenção:** `audit.log` é permanente e não expurgável — logo `cpf_hash` e `cpf_enc` **nunca
entram**. Não é ajustável depois: redação é no momento da escrita ou nunca.

---

## 1. Por que não é anonimização

Art. 5º, XI define anonimização como perda da possibilidade de associação "direta ou indireta" a
um indivíduo, por meios técnicos razoáveis. Art. 12 retira da LGPD só o dado anonimizado — e
ressalva expressamente o que possa ser revertido "utilizando exclusivamente meios próprios" ou
"com esforços razoáveis". Art. 13, §4º define pseudonimização como o tratamento em que a
associação só é possível "pelo uso de informação adicional mantida separadamente pelo controlador
em ambiente controlado e seguro". **É a descrição literal deste desenho:** o pepper é a informação
adicional, mantida separada pelo próprio controlador (ADR-0014).

Dois fatos técnicos fecham a questão:

1. **Determinismo é requisito, não acidente.** O HMAC precisa ser determinístico para sustentar
   `unique(cpf_hash)` e o lookup do login. Determinismo + domínio pequeno = reversão trivial: o
   espaço de CPF é de ~10⁹ valores válidos (11 dígitos, dois deles verificadores derivados). Quem
   tem o pepper monta a tabela inteira offline em minutos. Não é "esforço razoável" — é `for` loop.
2. **Mesmo sem o pepper**, o hash é um token estável e único que singulariza uma pessoa em toda a
   base e através do tempo. Identificador indireto é dado pessoal.

Conclusão: apagar `cpf_enc` e manter `cpf_hash` **não elimina nada — apenas dificulta**. A leitura
do orquestrador está correta, e o `pessoas_cpf_par_ck check ((cpf_hash is null) = (cpf_enc is
null))` já obriga a anular os dois juntos. O schema está certo; a trilha é que desfaz.

## 2. Por que isso bloqueia agora, e não depois

`audit.log` é append-only, encadeado por hash e permanente. Um `cpf_hash` gravado ali é
**irreparável**: removê-lo depois quebra a cadeia, e não removê-lo derrota toda anonimização
futura de ex-morador (parecer `off-boarding-ex-morador.md`, §6-bis da skill `lgpd-condominio`). A
rotina de 2031 apagaria o CPF de `pessoas` e a trilha o devolveria intacto. **Só existe um momento
para decidir isto: antes da primeira escrita em produção.** É a mesma classe do V9, não uma
variante menor dele.

## 3. Como redigir sem esvaziar a trilha

A redação não pode custar o propósito da trilha. Recomendação ao `eng-supabase`:

- Substituir o valor por marcador `[REDIGIDO]` em `antes` e `depois`, **antes** da serialização
  canônica — como já se faz com `cpf_enc`, para a cadeia permanecer consistente.
- Preservar o **fato** da mudança: a trilha continua provando que o CPF de tal `pessoa_id` foi
  alterado, quando e por quem. É isso que interessa auditar (Risco nº6, editora única). Ninguém
  audita a *correção* de um CPF lendo a trilha; o valor antigo não tem uso fiscalizatório.

## 4. Achado adicional — `nome`, `email` e `telefone` na trilha

Perguntaram sobre `cpf_hash`; o problema é mais amplo e a resposta não é simétrica. Todo
INSERT/UPDATE em `pessoas` grava a linha inteira em `antes`/`depois`. Minha posição, por coluna, e
é juízo de proporcionalidade (art. 7º, IX + art. 10), não regra de ouro — logo, revisável:

| Coluna | Decisão | Por quê |
|---|---|---|
| `cpf_enc`, `cpf_hash` | **Redigir** | Máximo poder de reidentificação, zero valor fiscalizatório no valor em si, e **CPF não existe em nenhum outro lugar permanente** do acervo — a trilha seria a única cópia eterna |
| `nome` | **Manter** | Redigir não compra privacidade nenhuma: nome de condômino já é permanente em atas e deliberações por necessidade legal (art. 16, I). Só destruiria a legibilidade da trilha exatamente onde mora o Risco nº6 |
| `email`, `telefone` | **Manter** | Valor fiscalizatório real e específico: provar que a editora trocou o e-mail de alguém e desviou o magic link é um ataque concreto neste desenho (SPEC §2.1). Poder de reidentificação bem menor que o do CPF |

**Consequência que precisa ser dita, não escondida:** a anonimização de ex-morador é, portanto,
**parcial quanto à trilha**. Ao responder pedido de eliminação (art. 18), a `editor` deve informar
isso ao titular com a base legal, em vez de afirmar eliminação completa. Afirmar completude e não
entregar é pior que a retenção em si.

## 5. Checklist

- [ ] `eng-supabase`: incluir `cpf_hash` na lista de redação do trigger — **bloqueia o V9**
- [ ] `eng-supabase`: marcador `[REDIGIDO]` preservando o fato da alteração (§3)
- [ ] `auditor-rls`: teste — UPDATE de `pessoas.cpf_hash` → `audit.log` sem o bytea original
- [ ] `juridico-lgpd`: registrar em `lgpd-condominio` §6-bis que a anonimização é parcial quanto à
      trilha, e que a resposta ao titular deve dizer isso
- [ ] Confirmar a redação literal de LGPD art. 5º, XI, art. 12 e art. 13, §4º em fonte primária na
      próxima invocação com `Bash` — a **substância** está firme; o texto exato não foi buscado
