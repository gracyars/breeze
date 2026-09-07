# Checklist de publicação — roda antes de cada exposição nova de dado

Documento vivo, dono `juridico-lgpd`. Atualizar quando o produto mudar de forma que o deixe
desatualizado — não quando alguém achar que ficaria mais bonito.

**Gatilho:** rodar antes de (a) mudar `documentos.status` de `em_revisao` para `publicado`;
(b) mudar `documentos.visibilidade` ou classificar página; (c) criar tela, view ou relatório que
mostre campo novo a um papel; (d) mandar dado para qualquer destino novo fora do Breeze.

**Item que falha é veto, não sugestão.** Veto não se negocia com outro agente: sobe ao
orquestrador (`docs/02-AGENTES.md`, item 3).

---

## Parte 1 — Todo caso

| # | Pergunta | Reprova quando |
|---|---|---|
| 1 | O dado está no inventário da skill `lgpd-condominio` §1? | Não está — atualizar o inventário e o registro de operações **antes** |
| 2 | Base legal exata? | A resposta é "consentimento" ou "não sei" (D2) |
| 3 | O papel que vai enxergar é o **mínimo** necessário? | `morador` veria o que é de `conselho`/`editor` |
| 4 | Inadimplência: agregada para `morador`? | Nominal fora de `conselho`/`editor`, **ou** agregado que permite inferir *quais* unidades (faixa com N=1, lista ordenada, total que dividido pela cota revela unidade única) |
| 5 | CPF: em claro só para `editor`, mascarado para `conselho`, ausente para `morador`? | Qualquer outra combinação — **veto automático** |
| 6 | `chunks` e `documento_paginas` espelham a RLS do documento pai, **chamando a mesma função**? | Predicado copiado em vez de chamado (Armadilha nº1, SPEC §7) |
| 7 | Retenção definida e com rotina de descarte/anonimização? | Retenção "a definir" |
| 8 | Visibilidade `publico`: só convenção e regimento passam sem redação | Ata, balancete ou qualquer outro proposto como `publico` sem etapa de anonimização — **veto automático**, e a decisão sobe à dona do projeto |
| 9 | Existe caminho testável de exercício de direito do titular sobre esse dado? | Não existe |
| 10 | O acesso expira sozinho, derivado de fato datado, com intervalo meia-aberto em instante? E **não há cache** (`use cache`, RSC, claim em token) entre o predicado e a tela? | Portão depende de flag que alguém precisa lembrar de virar; `date` em predicado de autorização; cache sobre papel/vínculo (ADR-0030) |
| 11 | Há PII de **terceiro não-condômino** (representante de fornecedor, responsável técnico, funcionário, instrutor, síndico terceirizado)? | Vai a `autenticado` ou `publico` sem decisão explícita — o padrão dessa classe é `conselho` |
| 12 | O dado cai em `audit.log`? | CPF em qualquer forma — inclusive `cpf_hash` — sem redação **na escrita**. Depois é tarde: corrigir quebra a cadeia |

## Parte 2 — Só para documento do acervo

| # | Pergunta | Reprova quando |
|---|---|---|
| 13 | Alguém **abriu** o documento e olhou a qualificação das partes? | Ninguém abriu. Varredura automática de padrão acha CPF formatado; não acha CPF escrito por extenso, nome em imagem, nem assinatura escaneada |
| 14 | Há **CPF ou RG em claro** no texto extraído? | Há, e não passou pela redação antes do chunk. Precedente vivo: a ata da AGI de 04.12.2025 traz CPF e RG completos do síndico |
| 15 | Documento **misto**? A visibilidade do arquivo é a da página **mais restritiva**? | Piso violado (ADR-0019). Ordem: `conselho < restrito < autenticado < publico` — `restrito` é mais permissivo que `conselho`, apesar do nome |
| 16 | Há **anexo replicado** cuja fonte canônica é outro documento? | A cópia pública é o continente em vez do arquivo autônomo (ADR-0028). Ex.: o regimento sai pelo arquivo #43, nunca pela ata que o embute |
| 17 | Há **lista nominal de pessoas** (presença em assembleia, brigada, votos, inadimplentes)? | Vai além de `autenticado`. Nominal de inadimplente vai além de `conselho` — veto |
| 18 | Documento de **fornecedor concorrente** (cotação, proposta em disputa)? | Vai além de `conselho` antes de haver decisão (parecer de 2026-09-04) |
| 19 | Há **dado sensível** (art. 11) — saúde, biometria, dado de criança identificada? | Há, e não há parecer específico. Regra abstrata de regimento ("exige atestado médico") **não** é dado de saúde; template biométrico é |
| 20 | Vai ao bucket `publicos`? | Sem 13–19 todos verdes. `publicos` é leitura sem login, pela internet inteira, e é irreversível na prática — o que foi indexado foi indexado |

## Parte 3 — Destino novo fora do Breeze

| # | Pergunta | Reprova quando |
|---|---|---|
| 21 | O destino é **operador** (art. 5º, VII)? Há contrato/DPA aceito e arquivado? | Não há |
| 22 | Há transferência internacional? Qual o mecanismo do Cap. V? | Não avaliado. Registrar como risco residual assumido é aceitável; ignorar não é |
| 23 | Entrou no registro de operações, com data? | Não entrou |
| 24 | O que ele recebe é o **mínimo** — e não "o dump inteiro porque é mais fácil"? | Envia mais do que a finalidade exige (art. 6º, III) |

---

## Registro de execuções

Uma linha por rodada. Quem rodou, sobre o quê, resultado. Item reprovado vira parecer.

| Data | Objeto | Quem | Resultado |
|---|---|---|---|
| 2026-09-07 | Subida a produção com os 43 documentos reais (Supabase hospedado + Vercel) | `juridico-lgpd` | **Aprovado com condição, em três portões.** Ver `pareceres/2026-09-07-producao-dado-real-supabase-vercel.md`. Itens 5, 8, 14, 20 pendentes até o Portão C |

---

## Histórico deste checklist

- **2026-09-07 — criado.** Consolida a lista de 12 itens da skill `lgpd-condominio` §8 e acrescenta
  a Parte 2 (documento do acervo, derivada dos achados da inspeção dos 43 arquivos reais) e a
  Parte 3 (destino externo, promovida a partir do ADR-0006/0024 quando a hospedagem inteira passou
  a ser tratamento por operador).
