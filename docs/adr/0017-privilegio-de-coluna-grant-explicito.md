# ADR-0017 — Privilégio de coluna: `GRANT` com lista explícita, nunca `REVOKE` de coluna

## Contexto

O ADR-0014 depende de uma exclusão de coluna: `pessoas.cpf_enc` (e `fornecedores.cpf_enc`) não
podem ser lidos pelo papel `authenticated`. O desenho original de `docs/schema.md` escrevia isso
da forma que parece idiomática e que aparece em quase toda discussão sobre o assunto:

```sql
grant  select                on public.pessoas to authenticated;
revoke select (cpf_enc)      on public.pessoas from authenticated;   -- NÃO FUNCIONA
```

O `eng-supabase` verificou ao vivo antes de aplicar em qualquer ambiente: **isso não bloqueia
nada.** Em Postgres, o privilégio efetivo sobre uma coluna é a **união** do ACL de tabela com o
ACL de coluna — nunca a subtração. `GRANT SELECT` na tabela concede leitura de todas as colunas,
inclusive as futuras, e um `REVOKE` de coluna posterior remove apenas uma entrada de ACL de
coluna que talvez nem exista. **A ordem não importa**: não há sequência de `GRANT`/`REVOKE` em que
"tabela inteira menos uma coluna" funcione.

O comando não falha, não avisa e não aparece em nenhum `\dp` que alguém leia com atenção. Ele
simplesmente não faz efeito. Foi a chegada mais perto que o projeto esteve de expor CPF cifrado a
todo usuário autenticado.

## Decisão

1. **Onde há coluna a excluir, nunca se concede `SELECT` de tabela inteira.** Concede-se coluna a
   coluna, com lista explícita:

```sql
revoke all on public.pessoas from public, anon, authenticated;
grant select (id, auth_user_id, nome, email, cpf_hash, cpf_ultimos_digitos, telefone,
              ativa, observacoes, criado_em, criado_por, atualizado_em)
  on public.pessoas to authenticated;          -- cpf_enc AUSENTE da lista, por construção
grant insert, update on public.pessoas to authenticated;
```

2. **`REVOKE <priv> (coluna)` é proibido no projeto como mecanismo de exclusão.** Se aparecer em
   migração, é bug, não estilo. Ele só tem sentido para desfazer um `GRANT` de coluna anterior.
3. **A exclusão vale só para `SELECT`.** `INSERT`/`UPDATE` de tabela inteira permanecem: é a
   `editor` cifrando e gravando o CPF. O que se veda é a **leitura de volta** — coerente com
   ADR-0014, onde a decifra acontece em rotina de servidor com a chave fora do banco.
4. **Coluna nova exige revisitar o `GRANT`.** É a consequência ruim e precisa ser dita: com lista
   explícita, uma coluna adicionada depois fica **invisível** até ser incluída na lista. Falha
   fechado — é o lado certo para falhar, mas produz o sintoma "a coluna existe e a aplicação não
   a vê", que custa uma hora a quem não conhece a regra. Toda migração que adiciona coluna a
   `pessoas` ou `fornecedores` precisa atualizar o `GRANT` no mesmo arquivo.
5. **Teste pgTAP obrigatório, um por coluna excluída:** `select cpf_enc from pessoas` como
   `authenticated` **falha** com erro de permissão. Teste de negação, não de caminho feliz — o
   caminho feliz passava com o desenho errado.
6. O `auditor-rls` varre a baseline atrás de outras ocorrências do padrão. Duas foram corrigidas
   (`pessoas`, `fornecedores`); a varredura procura a terceira.

## Consequências

- A superfície de leitura de `pessoas` e `fornecedores` passa a ser uma lista mantida à mão.
  Fricção real, aceita: é o único mecanismo que de fato exclui uma coluna.
- `SELECT *` como `authenticated` nessas tabelas passa a **falhar**, em vez de devolver a coluna
  proibida. A aplicação precisa listar colunas — o que já é boa prática e agora é obrigação.
- Este ADR generaliza para além do CPF: qualquer coluna que precise ficar fora do alcance de um
  papel segue a mesma forma.
- Lição de método, que vale mais que a regra: **a verificação ao vivo pegou o que a revisão de
  código não pegaria**, porque o SQL errado *parece* certo e não emite erro. Controle de
  segurança que não tem teste de negação executando é hipótese, não controle.

## Alternativas descartadas

- **`REVOKE SELECT (cpf_enc)` depois do `GRANT` de tabela.** Não funciona. Era o desenho anterior.
- **Inverter a ordem (`revoke` antes do `grant`).** Também não funciona — ACL de tabela e de
  coluna são união em qualquer ordem. Registrado porque é a "correção" que alguém tentará.
- **Mover `cpf_enc` para uma tabela satélite (`pessoas_cpf`) sem `GRANT` para `authenticated`.**
  Funciona e é robusto a coluna nova. Descartado por ora: adiciona uma tabela, um join e uma
  chance de as duas linhas divergirem, para resolver um problema que a lista explícita resolve.
  **É a saída se a lista de colunas virar fonte recorrente de erro** — reavaliar então.
- **Confiar em RLS.** RLS filtra linha, não coluna. Nunca foi opção.
- **Confiar na aplicação nunca selecionar a coluna.** Contraria o ADR-0012: verificação em código
  de aplicação é ergonomia, não fronteira.

## Status

Aceito. Complementa o ADR-0014 (item 4) e o ADR-0012 (item 7), cujo texto descrevia o mecanismo
errado. Os dois ADRs permanecem válidos no mérito — a decisão de excluir a coluna não muda, muda
o comando que a implementa.
