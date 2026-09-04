# ADR-0001 — Next.js App Router + TypeScript na Vercel

## Contexto

Um mantenedor, não especialista em infraestrutura (Briefing §2). Orçamento-alvo ~R$300/mês
(SPEC §1.2). Produto majoritariamente de leitura, com poucas telas de escrita concentradas no
papel `editor` (D4). Público em celular, faixa etária ampla, exigência de acessibilidade
(SPEC §6.5) — o que empurra para renderização no servidor e pouco JavaScript no cliente.

## Decisão

Next.js (App Router) + TypeScript, hospedado na Vercel. React Server Components para leitura,
Server Actions para escrita. **Não existe camada de API REST/GraphQL própria**: o acesso a dado
acontece por Server Component/Server Action falando com Supabase, ou pelo PostgREST do Supabase
quando o cliente precisa ler direto sob RLS.

TypeScript em modo `strict`, com os tipos do banco **gerados** a partir do schema no CI
(`supabase gen types typescript`) e commitados — o tipo do dado é derivado da migração, nunca
escrito à mão (ver ADR-0008).

## Consequências

- Não há contrato de API a versionar nem a documentar; em compensação, toda regra de acesso a
  dado precisa estar no banco, porque não há camada intermediária para escondê-la — o que
  reforça o ADR-0012 (RLS como fronteira única).
- Rotas da Vercel têm limite de corpo de requisição: upload de PDF não pode passar por Server
  Action. Daí o ADR-0004 (signed URL direto ao Storage).
- Funções serverless da Vercel têm timeout e não rodam binário nativo confortavelmente:
  processamento pesado sai da Vercel. Daí o ADR-0007.
- Vercel Pro (~R$110/mês) entra no orçamento do SPEC §1.2. Mudar de plataforma altera esse
  número e exige escalar (regra do arquiteto).
- Acoplamento a um fornecedor de hospedagem. Mitigação: Next.js roda em qualquer Node; a saída
  é um `next build` e um container, sem reescrita de aplicação.

## Alternativas descartadas

- **Self-host em VPS (Docker + Caddy).** Mais superfície de manutenção (SO, TLS, deploy,
  monitoramento) para um mantenedor não-especialista, com zero ganho nesta escala. Descartado.
- **SPA (Vite/React) + API própria.** Reintroduz a camada de API que o App Router elimina, com
  o custo de duplicar autorização em dois lugares. Pior para acessibilidade e para primeiro
  carregamento em celular modesto. Descartado.
- **Remix / SvelteKit.** Tecnicamente adequados; descartados por ecossistema menor de
  componentes acessíveis prontos e menor familiaridade dos agentes que vão construir.

## Status

Aceito. Formaliza ADR-1 da tabela do SPEC §1.1.
