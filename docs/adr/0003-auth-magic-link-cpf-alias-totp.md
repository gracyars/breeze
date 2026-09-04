# ADR-0003 — Auth: magic link, CPF como alias de identificação, TOTP/AAL2 para papéis privilegiados

## Contexto

Público não-técnico, faixa etária ampla (Briefing §3). O identificador que essa população
reconhece é o CPF — mas **CPF não é segredo e é enumerável** (SPEC §2.1, D2). Ao mesmo tempo,
o papel `editor` é único (D4) e concentra toda a escrita; o `conselho` lê inadimplência nominal
e anexos financeiros. Comprometer qualquer uma dessas duas contas é comprometer o produto
inteiro (Risco §8.6).

## Decisão

**Supabase Auth**, com fluxo único de entrada:

```
usuário digita CPF ou e-mail
  → servidor normaliza e calcula HMAC do CPF (ADR-0014) ou normaliza o e-mail
  → lookup em pessoas (cpf_hash ou email)
  → SE encontrou e a pessoa tem e-mail: envia magic link ao e-mail cadastrado
  → resposta ao navegador: SEMPRE idêntica ("se houver cadastro, enviamos um link")
```

Regras duras que decorrem disso:

1. **O CPF nunca concede sessão.** Ele só resolve qual e-mail recebe o link. Não existe senha.
2. **A resposta da tela de login é indistinguível** entre CPF/e-mail existente e inexistente,
   inclusive no tempo de resposta (o trabalho de HMAC + lookup roda sempre, mesmo sem match).
   Sem isso a tela vira oráculo de "esta pessoa mora aqui" — o que é vazamento de dado pessoal.
3. **Rate limit por IP e por identificador** no endpoint de início de login.
4. Pessoa sem e-mail cadastrado **não entra**; a `editor` cadastra (SPEC §2.1).
5. **TOTP obrigatório para `editor` e `conselho`.** Consequência técnica que não pode escapar:
   não basta pedir TOTP na tela. O nível de garantia entra na autorização — o helper
   `app.tem_papel()` só reconhece `editor`/`conselho` quando o JWT traz
   `aal = 'aal2'`. Sessão em AAL1 de uma pessoa do conselho é tratada como `morador`.
6. `sindico_terceirizado` **não é papel de conta** (D3). Não existe no enum de papel, não existe
   fluxo de convite para ele, e nenhuma tela pode criar essa conta. Ele é referenciado como
   fornecedor/sujeito de alerta.

## Consequências

- Zero senha guardada, zero fluxo de "esqueci minha senha", zero vazamento de senha reusada.
  Em compensação, **o e-mail do morador passa a ser o fator único** para `morador` — aceitável
  porque o morador só lê o próprio dado e o agregado.
- A caixa de entrada vira dependência de disponibilidade. Deliverability de magic link precisa de
  domínio próprio com SPF/DKIM/DMARC no provedor de e-mail; SMTP padrão do Supabase não serve
  para produção (limite baixo e reputação compartilhada). Item de F0 para `devops`.
- Perda do segundo fator do `editor` é incidente operacional sério: com D4 (editor único), não há
  outro editor para reconceder. Exige **código de recuperação impresso, guardado fora do sistema**,
  e um runbook. Sem isso, o produto tem um ponto único de falha humano.
- RLS lê `auth.uid()` nativamente; não há tradução de identidade entre aplicação e banco.
- `pessoas.auth_user_id` é a única amarra a `auth.users`, e é anulável: pessoa pode existir no
  cadastro sem nunca ter conta (ex.: ex-morador preservado para histórico).

## Alternativas descartadas

- **CPF + senha.** Enumeração trivial de morador e senha fraca garantida neste público. Descartado
  no SPEC §2.1 e em D2.
- **Clerk / Auth0.** Custo recorrente adicional e desacoplamento do RLS: a identidade passaria a
  vir de fora, exigindo sincronização com `auth.users` ou abandono de `auth.uid()` nas policies.
  Descartado.
- **OTP por SMS.** Custo por mensagem, dependência de operadora, e SIM-swap é vetor real contra
  um `editor` único.
- **TOTP opcional para `conselho`.** Descartado: o conselho lê inadimplência nominal — é dado
  pessoal negativo de terceiro (LGPD). Um fator só não sustenta esse acesso.

## Status

Aceito. Formaliza ADR-3 da tabela do SPEC §1.1 e travas D2/D3.
