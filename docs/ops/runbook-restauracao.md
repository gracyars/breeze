# Runbook de restauração — Breeze

Procedimento real de restore, para ser seguido ao pé da letra em um desastre (perda do projeto
Supabase, conta comprometida, corrupção de dados) e **testado de verdade a cada trimestre**. Um
runbook nunca testado é ficção — não é critério de "pronto" até a primeira execução real estar
registrada na seção 4.

Este documento cobre dois desastres diferentes, testados no mesmo ciclo trimestral:

- **Seção 3:** perda ou corrupção do dado (banco/Storage) — restore a partir do backup.
- **Seção 5:** perda do acesso de escrita da `editor` única — recuperação por código impresso
  (D9, `docs/04-DECISOES.md`).

Pré-requisito da seção 3: backup existente e íntegro, produzido por `scripts/backup.sh` (ver
`docs/ops/backup.md`). Sem backup, não há o que restaurar.

---

## 1. Quando acionar

- Projeto Supabase de produção inacessível, apagado ou com dados corrompidos além do que um
  estorno (SPEC §5.4) resolve.
- Suspeita de adulteração que quebra a hash-chain de `audit.log` (SPEC §7) — restaurar para uma
  versão anterior íntegra pode ser necessário para investigar, em paralelo com a escalação
  imediata do incidente.
- Teste trimestral programado (não é incidente — é exercício).

Restore falho durante o teste trimestral é **crítico**: escalar imediatamente à dona do projeto,
não apenas registrar no runbook e seguir em frente (ver `.claude/agents/devops.md`).

## 2. Pré-requisitos para executar

- Acesso ao bucket de backup (conta separada, credencial em `rclone.conf` — ver
  `docs/ops/backup.md` §3).
- `BACKUP_ENCRYPTION_KEY` para decifrar o dump.
- `supabase` CLI instalado, ou um projeto Postgres novo (local via `supabase start`, ou um
  projeto Supabase novo para o teste trimestral — **nunca sobrescrever produção durante um
  teste**, restaurar em ambiente isolado).
- `psql` / `pg_restore` compatível com a major version do Postgres do projeto (17, ver
  `supabase/config.toml`).

## 3. Procedimento passo a passo

### 3.1 Localizar e baixar o backup mais recente íntegro

```bash
# Lista os dumps disponíveis no bucket de backup, do mais recente para o mais antigo
rclone lsl breeze-backup:<bucket>/db/ | sort -k2 | tail -20

# Baixa o dump cifrado e o .sha256 correspondente
rclone copy breeze-backup:<bucket>/db/<ano>/breeze-db-<timestamp>.dump.gpg ./restore-tmp/
rclone copy breeze-backup:<bucket>/db/<ano>/breeze-db-<timestamp>.dump.sha256 ./restore-tmp/
```

### 3.2 Decifrar e verificar integridade

```bash
cd restore-tmp
gpg --batch --yes --decrypt --passphrase "$BACKUP_ENCRYPTION_KEY" \
  --output breeze-db-<timestamp>.dump \
  breeze-db-<timestamp>.dump.gpg

# Confere o hash contra o registrado no momento do backup — se não bater, o dump está
# corrompido ou adulterado; não prosseguir, buscar o dump da semana anterior e investigar.
sha256sum -c breeze-db-<timestamp>.dump.sha256   # ou: shasum -a 256 -c ...
```

### 3.3 Provisionar o destino da restauração

- **Teste trimestral:** `supabase start` local, ou um projeto Supabase novo dedicado a teste
  (nunca o de produção).
- **Desastre real:** novo projeto Supabase de produção, provisionado pela dona do projeto
  (provisionamento remoto pago não é decisão deste agente — ver `docs/ops/backup.md` §3).

Anotar a connection string do destino como `RESTORE_DB_URL`.

### 3.4 Restaurar o schema e os dados

```bash
# Formato custom (-Fc) permite restore com paralelismo e sem recriar o banco do zero
pg_restore \
  --no-owner \
  --no-privileges \
  --clean --if-exists \
  --jobs=4 \
  --dbname="$RESTORE_DB_URL" \
  breeze-db-<timestamp>.dump
```

`--clean --if-exists` remove objetos existentes antes de recriar — necessário para restaurar
por cima de um banco já inicializado pelo `supabase start` (que já tem os schemas `auth`,
`storage` etc. do Supabase). Em um projeto Supabase novo e vazio, o efeito é apenas idempotência.

### 3.5 Restaurar o Storage

```bash
# Direção invertida do backup: da conta de backup de volta para o Storage do destino.
rclone sync breeze-backup:<bucket>/storage-mirror <destino-storage-remote>: \
  --checksum --transfers 8
```

`<destino-storage-remote>` é um remoto `rclone` apontando para o endpoint S3 do Storage do
projeto de destino (mesmo mecanismo de configuração do remoto `breeze-prod-storage`, ver
`docs/ops/backup.md` §3).

### 3.6 Validação pós-restore (checklist obrigatório)

Não considerar o restore concluído sem confirmar, no destino restaurado:

- [ ] `select count(*) from documentos;` e `select count(*) from lancamentos;` batem (ordem de
      grandeza) com o esperado do backup mais recente.
- [ ] RLS está ativa nas tabelas críticas (`select relrowsecurity from pg_class where relname in
      ('documentos','chunks','documento_paginas','lancamentos');` — todas `true`).
- [ ] `audit.log` está presente e a hash-chain não está quebrada nas últimas N linhas (checagem
      manual do encadeamento `hash_registro = sha256(hash_anterior || linha canônica)` — SPEC §7).
- [ ] Um documento aleatório do Storage abre e corresponde ao registro em `documentos` (mesmo
      `sha256`).
- [ ] Login de teste (magic link) funciona no ambiente restaurado, se o teste incluir a camada
      de aplicação e não só o banco.
- [ ] Tempo total do procedimento (do início do download até a validação) registrado na seção 4
      — é o RTO real, não estimado.

### 3.7 Limpeza

Apagar o dump decifrado local (`breeze-db-<timestamp>.dump`) e o diretório `restore-tmp/` assim
que a validação terminar — não deixar dado pessoal decifrado em disco além do necessário.

```bash
cd .. && rm -rf restore-tmp
```

---

## 4. Registro de testes reais

Preencher a cada execução — teste trimestral **ou** incidente real. Sem entrada aqui, o restore
não é considerado validado, independentemente de o procedimento "parecer" correto.

O teste trimestral cobre **as duas seções deste runbook no mesmo ciclo**: restore de backup
(seção 3) e verificação de um código de recuperação da editora (seção 5). São desastres
diferentes; agendar os dois juntos evita que um deles vá ficando sempre para o próximo trimestre.

| Data | Tipo (teste trimestral / incidente real) | Backup usado (timestamp) | Destino | Resultado restore | RTO observado | Código de recuperação testado (nº do código / resultado) | Executado por | Observações |
|---|---|---|---|---|---|---|---|---|
| _(nenhum teste executado ainda)_ | — | — | — | — | — | — | — | Pendente — primeiro teste trimestral a agendar antes do fim de F0/início de F1. Até esta linha ganhar uma entrada real, nem o backup nem a recuperação de acesso atendem ao critério de pronto (ver `.claude/agents/devops.md`). |

Regra de cadência: uma entrada nova a cada trimestre corrido, no máximo. Se um trimestre passar
sem teste, isso é uma lacuna a escalar, não a esconder.

Se um teste **falhar** (restore ou código de recuperação): registrar o resultado como "Falhou"
com a causa, e escalar imediatamente à dona do projeto — não é suficiente documentar e seguir
para o próximo item do backlog.

---

## 5. Recuperação de acesso da `editor` única — código impresso (D9)

Decisão travada em `docs/04-DECISOES.md` (D9) e prevista em
`docs/adr/0003-auth-magic-link-cpf-alias-totp.md`: a `editor` é única (D4), TOTP é obrigatório
para `editor`/`conselho` (AAL2, ADR-0003/0012), e **não existe um segundo `editor` para
reconceder acesso**. A contenção é operacional, não técnica: códigos de recuperação impressos,
gerados uma vez e guardados fora de casa.

> **Isto precisa estar dito sem meias palavras:** o acesso de **escrita** do Breeze (publicar
> documento, conferir balancete, responder questionamento — tudo que só `editor` faz, SPEC §2.1)
> depende de duas coisas existindo ao mesmo tempo: o celular com o autenticador TOTP da editora,
> **ou** o papel com os códigos impressos. **Perder os dois ao mesmo tempo — celular e papel —
> é perda total do acesso de escrita do sistema.** Não há conta de emergência, não há segundo
> editor, não há "recuperar por e-mail" para o fator TOTP. O acervo continua **legível** por
> `conselho` e `morador` (a leitura não depende do TOTP da editora), mas ninguém publica nada
> novo, concilia balancete ou responde questionamento até o acesso de escrita ser restabelecido
> — o que, sem um código válido, significa provisionar uma conta `editor` nova do zero, com todo
> o atrito de identidade que isso implica.

### 5.1 Geração dos códigos (cerimônia única, repetida só quando os códigos acabarem ou forem trocados)

Executar no momento em que a `editor` fizer o enrollment do TOTP (primeira vez, ou depois de
uma troca de dispositivo):

```bash
# Gera 10 códigos de uso único, formato legível para digitação manual.
for i in $(seq 1 10); do
  printf "%02d  %s\n" "$i" "$(openssl rand -hex 5 | tr 'a-f' 'A-F' | sed 's/\(.\{4\}\)/\1-/g;s/-$//')"
done
```

Produz algo como `01  3F9A-2C11`. Cada linha é um código.

1. **Nunca guardar os códigos em claro em nenhum lugar digital do produto** — não em `.env`, não
   em tabela do banco, não em anexo de e-mail, não no gerenciador de tarefas. São segredo de
   acesso, não dado do condomínio, e ficam **fora do sistema** de propósito: se o banco vazar
   inteiro, os códigos continuam protegendo a conta.
2. Guardar, fora do produto, só o **hash SHA-256** de cada código, para permitir conferência no
   momento do uso (ex.: um arquivo num gerenciador de senha pessoal da dona do projeto, nunca no
   repositório git):
   ```bash
   echo -n "3F9A-2C11" | shasum -a 256
   ```
3. **Imprimir** os 10 códigos em claro, numerados, com uma linha de instrução ("código de
   recuperação de acesso do Breeze — usar só se perder o autenticador TOTP; ligar para [contato
   técnico]").
4. **Guardar o impresso fora de casa** — a decisão de onde exatamente (cofre no escritório,
   com um parente de confiança, caixa de segurança bancária) é da dona do projeto; a exigência
   dura é *fora de casa*, porque o cenário que este mecanismo existe para cobrir é justamente
   "perdi o celular e não consigo TOTP" — se o papel estiver na mesma casa/bolsa que o celular,
   um único evento (roubo, incêndio, celular caiu na piscina em férias) derruba os dois ao mesmo
   tempo e o código não protege nada.
5. Riscar fisicamente cada código assim que usado (uso único) e marcar o hash correspondente
   como consumido no registro de hashes.

### 5.2 Redenção — como um código volta a dar acesso

Um código de recuperação não é uma segunda senha que o próprio sistema valida automaticamente
numa tela — o Breeze não tem tela de "usar código de recuperação" no fluxo de login (isso seria
mais uma feature de auth para especificar e testar, fora do escopo deste agente). O código é a
**prova de posse fora de banda** que autoriza uma ação administrativa:

1. A editora, sem TOTP disponível, contata o suporte técnico/dona do projeto por um canal já
   conhecido (telefone, não e-mail — e-mail sozinho não prova identidade aqui).
2. Ela informa um dos códigos impressos, número da linha incluído.
3. Quem atende confere o hash do código informado contra o registro (§5.1, item 2). Bate →
   prossegue. Não bate → não prossegue, é um possível golpe de engenharia social.
4. Com a identidade confirmada, quem tem acesso ao projeto Supabase (hoje: a própria dona do
   projeto, via `SUPABASE_SERVICE_ROLE_KEY` ou dashboard) **remove o fator MFA/TOTP atual** da
   conta da `editor` no Supabase Auth (Dashboard → Authentication → Users → fator MFA da conta,
   ou API Admin `auth.admin.mfa.deleteFactor`/endpoint equivalente — **confirmar o nome exato do
   método contra a versão da API em uso no momento da execução real; não copiar cego de uma
   versão antiga da doc**).
5. A editora entra de novo por magic link (AAL1) e **reenrola um novo TOTP** na hora — sem isso
   ela segue tratada como `morador` pelo helper de autorização (ADR-0003/0012), sem escrita.
6. O código usado é riscado e marcado consumido (§5.1, item 5). Se restarem poucos códigos
   (regra prática: menos de 3), gerar um lote novo de 10 e repetir a cerimônia de guarda.

**Dependência técnica em aberto:** os passos 4–5 usam capacidade administrativa do Supabase Auth
que existe hoje via dashboard/API, mas o Breeze ainda não tem um procedimento **testado** ponta a
ponta nem um script de apoio para isso. Antes do primeiro teste trimestral real, `eng-supabase`
precisa confirmar (ou implementar, se faltar) o comando exato de remoção de fator MFA por
`service_role` e validar que o reenrollment funciona sem intervenção manual no banco. Até essa
confirmação, o item 4 deste procedimento é a maior incerteza do runbook — reportar ao
orquestrador se o primeiro teste trimestral esbarrar nisso.

### 5.3 Teste trimestral do código de recuperação

No mesmo ciclo do teste de restore (seção 3), sem esperar um incidente real:

1. Escolher **um** código impresso (não gastar mais de um por teste).
2. Rodar o procedimento de redenção completo (§5.2) **num ambiente de teste** — nunca revogar o
   TOTP da conta de produção da editora só para testar; usar uma conta `editor` de teste com o
   mesmo mecanismo, ou coordenar a janela com a dona do projeto se o teste tiver que ser na conta
   real.
3. Confirmar que a conta testada, ao final, consegue publicar algo trivial (ou simular a
   permissão) só depois do reenrollment — prova de que o caminho de escrita realmente dependia
   do TOTP e foi restabelecido, não que "parecia" ter funcionado.
4. Registrar o resultado na tabela da seção 4 (coluna "Código de recuperação testado").
5. Se o teste falhar (código não bate, remoção de fator não funciona, reenrollment trava): é
   crítico, mesma regra da seção 1 — escalar imediatamente à dona do projeto.
