# ADR-0014 — CPF: HMAC determinístico para lookup, cifra reversível feita na aplicação

## Contexto

SPEC §2.1 exige duas propriedades que puxam em direções opostas: **lookup determinístico** pelo
CPF (para resolver o login por CPF) e **reversibilidade** (a `editor` precisa ver o CPF em claro
para conferir com documento da administradora). Ao mesmo tempo, o CPF é enumerável: um hash
determinístico sem segredo é quebrável por força bruta em minutos — o espaço de CPFs válidos é
de ~1,1 bilhão, e o dígito verificador reduz o trabalho.

Base legal LGPD: obrigação legal e legítimo interesse (CC art. 1.348, VIII), **não consentimento**
(SPEC §7). Minimização: CPF em claro só para `editor`; para o `conselho`, sempre mascarado.

## Decisão

Duas colunas em `pessoas`, mais uma de exibição:

| Coluna | Tipo | Conteúdo | Segredo usado |
|---|---|---|---|
| `cpf_hash` | `bytea` (32 B), `unique` | `HMAC-SHA256(cpf_normalizado, PEPPER)` | `CPF_PEPPER` |
| `cpf_enc` | `bytea` | `nonce(12) || AES-256-GCM(cpf) || tag(16)` | `CPF_ENC_KEY` |
| `cpf_ultimos_digitos` | `char(3)` | 3 dígitos, para exibição mascarada | — |

Regras duras:

1. **Nenhum segredo entra no banco.** `CPF_PEPPER` e `CPF_ENC_KEY` vivem no gerenciador de
   segredos da plataforma, injetados como variável de ambiente no runtime (SPEC §2.1: "pepper em
   variável de ambiente, fora do banco"). Consequência: quem obtém um dump do banco **não**
   obtém CPF nenhum — nem por lookup, nem por decifra.
2. **HMAC e cifra acontecem na aplicação (Node)**, nunca em função SQL. O banco recebe `bytea`
   pronto. Não existe `pgcrypto` com chave em coluna, não existe `pgsodium` TCE, não existe
   `Vault` guardando a chave ao lado do dado — se a chave está no banco, o dump volta a valer.
3. **CPF em claro nunca trafega para o navegador do `conselho`.** O `conselho` vê
   `***.***.789-**` a partir de `cpf_ultimos_digitos`. `cpf_ultimos_digitos` guarda os dígitos
   7–9 (os anteriores ao verificador) e **jamais** os dígitos verificadores — deles se deriva
   material suficiente para reduzir busca.
4. **`REVOKE SELECT (cpf_enc) ON pessoas FROM authenticated`** (ADR-0012, item 7). A decifra
   acontece em rotina de servidor que (a) confirma `editor` com AAL2, (b) registra em
   `audit.acesso` com motivo, (c) devolve o valor sem cachear. Ver CPF é evento auditado, não
   consulta.
5. **Normalização antes de tudo:** só dígitos, 11 caracteres, com validação de dígito verificador.
   `123.456.789-09` e `12345678909` produzem o mesmo `cpf_hash`. Sem isso, o `unique` não protege.
6. **Tempo constante no login** (ADR-0003): o HMAC e o lookup rodam mesmo quando o input é
   inválido ou inexistente.
7. **CPF de fornecedor pessoa física** segue exatamente o mesmo tratamento (`fornecedores.cpf_hash`).

## Consequências

- **Rotação de segredo é operação séria e precisa de runbook.** Rotacionar `CPF_ENC_KEY` é
  decifrar e recifrar toda `pessoas` (barato: ~50 linhas). Rotacionar `CPF_PEPPER` é recomputar
  todo `cpf_hash` — só é possível porque `cpf_enc` permite recuperar o CPF; **perder
  `CPF_ENC_KEY` congela o pepper para sempre**. Ambas as chaves precisam de cópia em cofre físico
  ou gerenciador externo, fora da conta do provedor (Risco §8.5, bus factor = 1).
- Segredos são **por ambiente, sem interseção** (ADR-0009). `cpf_hash` de staging não bate com o
  de produção — é o comportamento desejado.
- Não é possível pesquisar CPF por prefixo ou parcial no banco. Correto: busca parcial de CPF é
  enumeração com outro nome.
- `audit.log` **redige** `cpf_enc` (ADR-0013) — a trilha não vira segunda cópia do dado.
- Anonimização de ex-morador (SPEC §7) é `cpf_hash = null, cpf_enc = null,
  cpf_ultimos_digitos = null`, preservando agregados e a integridade referencial do histórico.
- A aplicação carrega uma dependência de cripto correta (AES-256-GCM com nonce aleatório por
  operação, **nunca reusado**). É código pequeno e sensível: merece teste unitário e revisão.

## Alternativas descartadas

- **Guardar CPF em claro com RLS.** RLS não protege de dump, de backup vazado, nem de
  `service_role`. Descartado.
- **Hash sem pepper (SHA-256 puro).** ~1,1 bilhão de candidatos válidos: tabela completa em
  minutos com hardware comum. É pseudonimização de fachada.
- **`pgsodium` / Transparent Column Encryption do Supabase.** Caminho descontinuado, e mesmo
  quando disponível colocava a chave sob o mesmo perímetro do dado — perdendo a única propriedade
  que importa: dump inútil sem a chave. *(Confiança média-alta sobre o status de descontinuação;
  irrelevante para a decisão, porque a objeção arquitetural vale de qualquer forma.)*
- **`pgcrypto` com chave passada por parâmetro na consulta.** A chave aparece em
  `pg_stat_activity` e nos logs de consulta do provedor. Descartado.
- **Cifra determinística (AES-SIV) numa única coluna, servindo lookup e decifra.** Elegante e
  reduz para uma coluna — descartado porque acopla a capacidade de busca à posse da chave de
  decifra: qualquer rotina que precise buscar passaria a poder decifrar. Duas chaves, dois
  privilégios.
- **Não guardar CPF.** Foi considerado seriamente (minimização é a defesa mais forte). Inviável:
  o CPF é o identificador que o morador reconhece no login (D2) e é o campo de conferência contra
  documento da administradora.

## Status

Aceito.
