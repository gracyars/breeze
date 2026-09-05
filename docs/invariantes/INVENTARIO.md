# Inventário de invariantes de autorização

Toda função em `app.*` referenciada por policy, e todo trigger de autorização, precisa de um
arquivo `INV-*.md` preenchido. **Célula vazia bloqueia merge** — ver `README.md`.

Backlog datado: preenchimento **antes de produção**, não antes do próximo merge. O gate passa a
valer imediatamente para invariante **nova ou alterada**.

| # | Invariante | ADR | Estado | Dono |
|---|---|---|---|---|
| INV-01 | Nível efetivo da página = override da própria página, ou piso do documento — **e nada mais** | 0023 | a preencher (o predicado muda: remoção do ramo não-local) | `eng-supabase` |
| **INV-02** | **Existe sempre ao menos um `editor` vigente** | 0022 | **preenchida — exemplo de referência** | `eng-supabase` |
| INV-03 | Piso: `ordem(documentos.visibilidade) <= ordem(cada página sua)` | 0019 | a preencher | `eng-supabase` |
| INV-04 | Chunk não cruza fronteira de visibilidade no seu intervalo | 0018, 0021 | a preencher — inclui o segundo caminho (reclassificação) | `eng-supabase` |
| INV-05 | `documento_visivel` ⊇ união do que suas páginas liberam (arquivo nunca mais aberto que conteúdo) | 0019 | a preencher | `eng-supabase` |
| INV-06 | Papel privilegiado exige AAL2 e mandato vigente | 0003, 0012 | a preencher | `eng-supabase` |
| INV-07 | `lancamentos` sem `UPDATE`/`DELETE`, inclusive `service_role` | 0011 | a preencher | `eng-supabase` |
| INV-08 | Estorno: valor exato inverso, mesma conta/tipo/fundo, uma vez só, não estornável | 0011 | a preencher | `eng-supabase` |
| INV-09 | `audit.log` append-only e cadeia íntegra (inclui contiguidade **não** assumida) | 0013, 0021 | a preencher — F4 é o V5-R | `eng-supabase` |
| INV-10 | `cpf_enc` fora do `GRANT SELECT`; nenhuma coluna nova entra por omissão | 0017 | a preencher | `eng-supabase` |
| INV-11 | Snapshot de signatário congela na assinatura e é imutável | 0020 | a preencher | `eng-supabase` |
| INV-12 | Acesso cessa em `vinculos.fim` + 0 dias (`eh_autenticado` derivada de vínculo/papel) | parecer `juridico-lgpd` C1 | a preencher — **bloqueia produção** | `eng-supabase` |

**Ordem sugerida de preenchimento:** INV-12 e INV-01 primeiro (bloqueiam produção e o predicado
está mudando), depois INV-03/04/05 (a família de visibilidade, onde três das quatro rodadas
falharam), depois o resto.

## Observação de método

O INV-02 achou uma quarta lacuna (`UPDATE papeis.pessoa_id`) que nenhuma das três rodadas de
auditoria tinha nomeado, e ela apareceu **só porque a linha foi gerada pelo produto cartesiano**,
não pensada. É a evidência de que o formato funciona: a matriz encontra o que a imaginação não
enumera.
