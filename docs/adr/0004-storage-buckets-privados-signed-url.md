# ADR-0004 — Supabase Storage: buckets privados, upload por signed URL, download por URL assinada de TTL curto

## Contexto

O acervo são PDFs, parte escaneada — arquivos grandes. Rota da Vercel tem limite de corpo
(ADR-0001). Os anexos financeiros (nota fiscal, cotação, comprovante) são o material mais
sensível do produto e são visíveis só a `conselho` e `editor` (SPEC §2, §7). Um arquivo servido
por URL pública é uma autorização que a RLS não alcança.

## Decisão

Três buckets, com regras distintas:

| Bucket | Público | Conteúdo | Acesso |
|---|---|---|---|
| `documentos` | não | todo o acervo (atas, balancetes, contratos, laudos) | signed URL gerada no servidor após checagem de papel/visibilidade |
| `anexos-financeiros` | não | anexos de `lancamentos` | signed URL, TTL 60–300 s, só `conselho` e `editor` |
| `publicos` | **sim** | apenas convenção e regimento | URL direta, cacheável |

Regras duras:

1. **Upload sempre por signed upload URL**: o browser envia direto ao Storage; a Server Action só
   cria a linha em `documentos` (status `pendente`) e enfileira (SPEC §3.1).
2. **Download nunca por URL persistente.** A URL assinada é gerada por requisição, no servidor,
   depois de avaliar papel e `visibilidade`. TTL curto. **Nunca embutida em página cacheada na
   CDN** (SPEC §7) — a rota que gera a URL é `no-store`.
3. O bucket `publicos` só recebe arquivo cujo `documentos.tipo` tem `permite_publico = true`
   (hoje: convenção e regimento). Publicar ali é decisão explícita da `editor`, e o schema
   bloqueia o resto (ver `schema.md`, trigger de visibilidade).
4. `storage.objects` também tem RLS, espelhando `app.documento_visivel()`. Signed URL contorna
   RLS por construção — por isso a checagem de papel acontece **antes** de assinar; a RLS em
   `storage.objects` é a segunda camada, para acesso direto com o JWT do usuário.
5. O nome do objeto **não carrega informação**: `documentos/<uuid>.pdf`, nunca
   `documentos/ata-assembleia-2024-inadimplentes.pdf`. Nome de arquivo é metadado que vaza.

## Consequências

- Compatível com S3; migrar Storage é copiar bucket e trocar cliente.
- O caminho feliz do upload tem três passos (assinar → enviar → registrar), e o segundo pode
  falhar sozinho, deixando linha `pendente` sem arquivo. Precisa de reconciliação: job que
  marca `erro` documento `pendente` há mais de N horas sem objeto correspondente.
- Dedupe por `sha256` (SPEC §3.1) exige hash **no cliente antes do upload** ou no worker depois.
  Decisão: hash no worker (o cliente pode mentir), com `unique` em `documentos.sha256` como trava
  final. O upload duplicado custa banda, não integridade.
- Espelho do Storage em conta separada é parte do backup (SPEC §7) e não vem de graça: é rotina
  do `devops`, não do provedor.

## Alternativas descartadas

- **Upload via função Next.** Quebra em PDF grande (limite de corpo). Descartado no SPEC §1.1.
- **Bucket único com pastas.** Um erro de policy expõe anexo financeiro junto com ata pública.
  Separação física de bucket é a fronteira mais barata de auditar.
- **Servir PDF por rota proxy do Next.** Faz todo byte passar pela Vercel (custo, timeout), sem
  ganho de segurança sobre URL assinada de TTL curto.
- **Acervo inteiro em bucket público.** Contraria Briefing §7 decisão 1 e SPEC §7: atas e
  balancetes carregam nome, unidade e às vezes CPF.

## Status

Aceito. Formaliza ADR-4 da tabela do SPEC §1.1.
