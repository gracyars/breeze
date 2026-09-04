# Breeze — Skills

Princípio de segurança adotado: **skill de infraestrutura vem só de fonte oficial** (Anthropic,
Vercel, Supabase). Qualquer skill que toque OCR de documento fiscal ou lógica contábil é
**escrita internamente** — skills de marketplace carregam risco de prompt injection e de código
não auditado, e aqui elas processariam dado pessoal de moradores.

## Já disponíveis nesta máquina — usar, não recriar

| Skill | Uso no projeto |
|---|---|
| `vercel:nextjs` | App Router, Server Components, Server Actions |
| `vercel:shadcn` | Base do design system |
| `vercel:ai-sdk` | RAG, embeddings, streaming, tool calling para citação |
| `vercel:auth` | Padrões de integração de autenticação |
| `vercel:next-cache-components` | Cache e PPR nas páginas financeiras |
| `vercel:deployments-cicd`, `vercel:vercel-cli`, `vercel:deploy` | Pipeline e deploy |
| `vercel:react-best-practices` | Revisão de TSX |
| `supabase-postgres-best-practices` | Schema, RLS, índices, pgvector, migrações, Storage |
| `devops-engineer` | CI/CD, observabilidade, incidente |
| `code-review`, `security-review` | Revisão de diff e checklist de segurança |
| `web-design-guidelines` | Auditoria WCAG |
| `ui-ux-pro-max` | Padrões de dashboard e tabela |
| `dataviz` | Gráficos do financeiro, paleta acessível |
| `agent-browser` | QA exploratório (não substitui Playwright versionado) |

## Fontes oficiais para buscar o que faltar

| Fonte | URL | Instalação |
|---|---|---|
| anthropics/skills | github.com/anthropics/skills | copiar para `.claude/skills/` |
| anthropics/claude-plugins-official | github.com/anthropics/claude-plugins-official | `/plugin` → Discover |
| supabase/agent-skills | github.com/supabase/agent-skills | `npx skills add supabase/agent-skills` |
| vercel-labs/skills (CLI do ecossistema) | github.com/vercel-labs/skills | `npx skills add ...` |
| vercel-labs/agent-skills | github.com/vercel-labs/agent-skills | via plugin Vercel |

Agregadores comunitários (`awesome-claude-skills`, `claudemarketplaces.com`, `mcpmarket.com`,
`skills.sh`) servem para **descobrir ideias**, não para instalar direto neste projeto.
Nenhum deles é auditado.

## A instalar, com avaliação prévia

- Testes: Playwright + Vitest. Os pacotes de skill de terceiros com esses nomes **não foram
  verificados como repositórios reais** — provável que valha escrever uma skill interna curta
  em vez de importar.
- OCR/PDF: existem skills comunitárias, **todas não auditadas**. Decisão: interna.

## Skills internas a escrever (não existem prontas)

1. **`condominio-plano-de-contas`** — plano de contas brasileiro, rateio ordinário vs extraordinário, fundo de reserva, regras de classificação.
2. **`condominio-documentos`** — taxonomia documental, o que cada tipo contém, o que se busca dentro de cada um, quem pode ver.
3. **`condominio-legal`** — Código Civil arts. 1.331+, Lei 4.591/64, quórum por matéria, dever de prestação de contas. **Cada afirmação com citação verificada; nada de artigo inventado.**
4. **`lgpd-condominio`** — base legal, minimização, inadimplência nominal, retenção, anonimização.
5. **`ocr-documento-fiscal-br`** — heurística de qualidade de OCR, layout de balancete e NF, armadilhas de dígito, travas de consistência contábil.
6. **`rag-citacao-juridica-ptbr`** — formato de citação (documento, página, trecho literal), regra de recusa, proibição de sintetizar valor.

Escrever as skills 1–4 antes de F2. As 5 e 6 antes de F1 — o `eng-ingestao` e o `eng-busca` dependem delas.
