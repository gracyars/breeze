# Breeze — Design system (F0)

Base visual do produto. Quem compõe tela (`front-morador`, `front-gestao`) consome daqui e não
redefine token, cor nem tamanho de fonte na feature.

Fonte normativa: SPEC §6.1–§6.6 e briefing §3. Onde este documento e o SPEC divergirem, o SPEC
vence — abra questão com o orquestrador em vez de contornar.

Arquivos:

| O quê | Onde |
|---|---|
| Tokens (cor, tipografia, espaço, raio, sombra) | `app/globals.css` |
| Fontes | `app/layout.tsx` |
| Primitivos | `components/ui/**` |
| Vitrine viva (alvo dos testes) | `app/design-system/page.tsx` → rota `/design-system` |
| Regras de gráfico | `docs/design/graficos.md` |
| Contraste travado no CI | `tests/unit/contraste-tokens.test.ts` |
| Contraste, escala e alvo renderizados | `tests/a11y/*.spec.ts` |

Tailwind v4: a configuração é o bloco `@theme` do CSS. **Não existe `tailwind.config.ts`** e não
deve passar a existir — token novo entra em `app/globals.css`.

---

## 1. Princípios

1. **Parecer um extrato bancário, não uma startup** (§6.6). Sóbrio, previsível, sem efeito.
2. **Hierarquia por peso tipográfico e espaço em branco**, nunca por cor.
3. **Cor nunca é a informação.** Todo status carrega palavra; todo gráfico carrega o número escrito.
4. **Acessibilidade ganha de estética**, sempre, por decisão registrada. O público inclui pessoa
   idosa com baixa familiaridade digital, em celular (briefing §3).
5. **Nenhum número sem proveniência** (§6.5): data, quem publicou, natureza e link para a fonte.
   Por isso `SeloProveniencia` é primitivo, não enfeite de feature.
6. **Fonte primária, síntese secundária** (§6.2). O componente de citação impõe isso por tipo.

## 2. O que é proibido

- Gradiente, sombra colorida, glassmorphism, mascote, ilustração decorativa.
- Segundo azul, ou qualquer outra cor de ação. É **um** azul (`--color-acao`).
- Verde ou vermelho **decorativos** — cor como enfeite, sem significado. Vale só onde carrega
  semântica: status financeiro, erro, confirmação. Proibido: badge "novo" verde, faixa vermelha
  de destaque, ícone colorido sem estado por trás.
- Botão destrutivo vermelho. Aqui o argumento não é a cor decorativa, é a segurança: ação
  destrutiva é `secundaria` com confirmação explícita em texto, não um botão vermelho que se
  clica por reflexo.
- Tamanho de texto abaixo de 16px. `text-xs` e `text-sm` foram **removidos** do Tailwind: se
  alguém escrever a classe, ela simplesmente não existe.
- Alvo clicável abaixo de 48px. Exceção única: link dentro de texto corrido (marque
  `data-inline="true"`).
- Altura fixa em container de texto, tamanho de fonte em `px`, `100vh` travando conteúdo — tudo
  quebra em 200% de zoom.
- Gráfico de pizza/rosca, séries sobrepostas, gráfico sem rótulo no elemento. Ver
  `docs/design/graficos.md`.
- Modo escuro: **não existe em F0**. Não é aversão, é escopo — exigiria uma segunda auditoria de
  contraste inteira. Se entrar, entra com a tabela de contraste refeita.

---

## 3. Cor

Base neutra cinza-azulada quase papel, um azul profundo de ação, verde e vermelho só para
dinheiro (§6.6).

### Neutros

| Token | Hex | Uso |
|---|---|---|
| `--color-papel` | `#f7f8fa` | fundo da página |
| `--color-superficie` | `#ffffff` | card, campo, tabela |
| `--color-superficie-alt` | `#f2f5f8` | cabeçalho de tabela, linha zebrada |
| `--color-superficie-muda` | `#eef1f5` | desabilitado, bloco secundário (síntese) |
| `--color-tinta` | `#16202c` | texto principal |
| `--color-tinta-suave` | `#445260` | texto secundário |
| `--color-tinta-fraca` | `#5a6a78` | meta e placeholder |
| `--color-borda` | `#c6ceda` | hairline **decorativa** |
| `--color-borda-forte` | `#7d8b99` | limite que informa: campo, tabela, controle |

Card branco sobre papel tem 1,06:1 — invisível sozinho. Por isso `Card` já vem com borda: não é
opcional.

### Ação

| Token | Hex | Uso |
|---|---|---|
| `--color-acao` | `#14417a` | link, botão primário, série principal de gráfico |
| `--color-acao-forte` | `#0e3160` | hover |
| `--color-acao-ativa` | `#0a2549` | pressed |
| `--color-acao-suave` | `#e7edf6` | realce de termo buscado, hover de item |
| `--color-foco` | `#14417a` | anel de foco (3px, offset 2px) |

### Verde e vermelho — só com significado

| Token | Hex | Significado |
|---|---|---|
| `--color-positivo` / `-suave` | `#0c4e2f` / `#edf6f1` | dentro do orçamento, saldo positivo, quitado |
| `--color-negativo` / `-suave` | `#8e1c24` / `#fbeeee` | acima do orçamento, saldo negativo, em atraso |
| `--color-atencao` / `-suave` | `#6b4700` / `#fbf1e0` | severidade de alerta (§5.3) |
| `--color-erro` / `-suave` | `#8e1c24` / `#fbeeee` | erro de formulário |

`erro` repete o hex de `negativo` de propósito: no produto existe **um** vermelho. São tokens
separados porque o significado é outro — se um dia divergirem, será por decisão, não por
descuido (há teste travando a igualdade).

Verde e vermelho escuros são **indistinguíveis entre si** para quem tem deuteranopia — e a
luminância deles é próxima de propósito (ambos AAA). É exatamente por isso que `BadgeStatus`
exige texto: a cor é redundância, a palavra é a informação. Isso está travado em teste.

### Gráfico

`--color-grafico-realizado` (= azul de ação), `--color-grafico-orcado` `#9aa9b8`,
`--color-grafico-contorno` `#5a6a78`, `--color-grafico-eixo` `#7d8b99`. Regras em
`docs/design/graficos.md`.

### Contraste medido

Calculado pela fórmula WCAG 2.x e verificado em `tests/unit/contraste-tokens.test.ts`.

| Frente | Fundo | Razão | Nível |
|---|---|---|---|
| tinta | papel | 15,5:1 | AAA |
| tinta | superficie-alt | 15,0:1 | AAA |
| tinta-suave | papel | 7,5:1 | AAA |
| tinta-suave | superficie-muda (desabilitado) | 7,1:1 | AAA |
| tinta-fraca | papel | 5,2:1 | AA |
| acao | papel | 9,6:1 | AAA |
| acao | acao-suave | 8,6:1 | AAA |
| branco | acao (botão primário) | 10,2:1 | AAA |
| branco | acao-forte (hover) | 12,9:1 | AAA |
| positivo | papel / positivo-suave | 9,2:1 / 8,9:1 | AAA |
| negativo | papel / negativo-suave | 8,4:1 / 7,9:1 | AAA |
| atencao | papel / atencao-suave | 7,8:1 / 7,4:1 | AAA |
| erro | papel / branco | 8,4:1 / 9,0:1 | AAA |
| borda-forte | papel / branco | 3,3:1 / 3,5:1 | 1.4.11 ok |
| grafico-contorno | papel | 5,2:1 | 1.4.11 ok |

Todo texto financeiro fica em AAA, como o §6.5 exige. `tinta-fraca` é o único token em AA e é
proibido em valor monetário — use `tinta` ou `tinta-suave`.

---

## 4. Tipografia

### Famílias, e por quê

**Corpo jurídico — `Source Serif 4`** (`--font-serif`, utilitário `texto-legal`).
Serifada humanista desenhada para leitura imersiva em tela: altura-x alta, aberturas largas,
contraste de traço baixo. Convenção e regimento são leitura longa e contínua (§6.3) — serifada
segura melhor a linha e sinaliza "texto oficial" sem precisar de moldura. Cobertura latin-ext
completa para PT-BR. Fallback real: `Source Serif Pro, Charter, Georgia, Times New Roman, serif`
— Georgia existe em Windows e macOS e tem métrica próxima o bastante para não dar salto.

**UI e números — `IBM Plex Sans`** (`--font-sans`).
Humanista neutra, de origem institucional, glifos bem diferenciados e `tnum` (algarismo tabular)
de verdade na fonte. Preferida a Inter, que é a tipografia-padrão de produto de startup — o
oposto do registro pedido no §6.6. Fallback: `Segoe UI, system-ui, -apple-system, Helvetica Neue,
Arial, sans-serif`.

**Número financeiro:** utilitário `numero` → `font-variant-numeric: tabular-nums lining-nums`.
Obrigatório em qualquer coluna ou lista de valor. Sem tabular, a coluna não alinha e o conselho
perde a leitura vertical do balancete. `TableCell numerico` e os gráficos já aplicam.

### Escala

Raiz em `100%` — a preferência de fonte do navegador do morador vale. Tudo em `rem`.

| Classe | Tamanho | Entrelinha | Uso |
|---|---|---|---|
| `text-4xl` | 48px | 1.1 | número único do mês (§6.4, camada 1) |
| `text-3xl` | 36px | 1.2 | título de página |
| `text-2xl` | 30px | 1.25 | título de seção |
| `text-xl` | 24px | 1.35 | título de card |
| `text-lg` | 20px | 1.55 | destaque, trecho citado |
| `texto-legal` | 20px serifada | 1.75 | corpo de convenção e regimento, medida 68ch |
| `text-base` | **18px** | 1.6 | corpo padrão (alvo do §6.5) |
| `text-meta` | **16px** | 1.5 | rótulo, badge, legenda — piso absoluto |

Pesos: 400 corpo, 500 número em tabela, 600 título e botão, 700 só em ênfase dentro de frase.

---

## 5. Espaço, raio, sombra

- Espaçamento: escala 4px do Tailwind (`gap-2`, `p-5`…). Ritmo padrão de bloco: `gap-4` interno,
  `gap-8` entre seções. Generoso de propósito — dedo idoso erra alvo colado.
- `alvo-toque` (48px) e `alvo-toque-lg` (56px, CTA principal no celular): utilitários; aplique em
  tudo que é clicável.
- `medida-leitura` (68ch): limite de linha de texto longo.
- Raio: `rounded-md` (6px) em botão e campo, `rounded-lg` (10px) em card, `rounded-sm` (4px) em
  badge. Nada arredondado demais — sobriedade institucional.
- Sombra: `shadow-sm` em card, `shadow-lg` só em camada flutuante. **O limite vem da borda, não da
  sombra.**

---

## 6. Componentes

Importe pelo barril: `import { Button, Card } from "@/components/ui";`

### `Button`

```tsx
<Button>Ver boleto</Button>
<Button variante="secundaria">Baixar PDF</Button>
<Button variante="discreta" tamanho="compacta">Limpar filtros</Button>
<Button asChild><Link href="/financeiro">Ver o financeiro</Link></Button>
```

Variantes: `primaria` (uma por tela), `secundaria`, `discreta`. Tamanhos: `md` (48px), `lg`
(56px), `compacta` (48px de altura, menos respiro lateral). **Não existe variante destrutiva
vermelha** — ação destrutiva é `secundaria` com confirmação explícita em texto.
Verbo concreto no rótulo (§6.5): "Ver boleto", nunca "Acessar módulo financeiro".

### `CampoTexto` / `Input`

```tsx
<CampoTexto
  rotulo="CPF ou e-mail"
  ajuda="Enviamos um link de acesso para o e-mail cadastrado."
  erro={erro}
/>
```

Rótulo visível sempre; placeholder nunca substitui rótulo. `erro` liga `aria-invalid` e
`aria-describedby`, pinta a borda de `erro` e renderiza a mensagem em vermelho **com o prefixo
literal "Erro:"** — a cor é convenção, a palavra é o que sustenta quem não a distingue. Nunca
remova o prefixo confiando na cor.

### `Card`

`Card` / `CardHeader` / `CardTitle` (`as` para o nível de heading correto) / `CardDescription` /
`CardContent` / `CardFooter`. Borda obrigatória já embutida.

### `Badge` e `BadgeStatus`

```tsx
<Badge>Ata</Badge>
<Badge variante="rascunho">Rascunho</Badge>
<BadgeStatus status="negativo">acima do orçamento</BadgeStatus>
```

`Badge`: `neutro` (tipo de documento, faceta), `acao`, `rascunho` (§6.1 — rascunho e publicado
são visualmente distintos). `BadgeStatus`: `positivo | negativo | atencao | neutro`, `children`
textual **obrigatório** por tipo, glifo redundante para daltonismo.

### `Table`

```tsx
<Table rotulo="Lançamentos de agosto de 2025">
  <TableCaption>Lançamentos de agosto de 2025</TableCaption>
  <TableHeader><TableRow><TableHead numerico>Valor</TableHead></TableRow></TableHeader>
  <TableBody><TableRow><TableCell numerico>R$ 4.320,00</TableCell></TableRow></TableBody>
</Table>
```

`rotulo` é obrigatório: a área de rolagem é `role="region"` com `tabIndex=0`, para tabela larga
ser alcançável por teclado. `numerico` liga algarismo tabular e alinhamento à direita.

### Par de citação — `TrechoFonte` + `RespostaSintetizada`

```tsx
<RespostaSintetizada
  fontes={
    <TrechoFonte tipo="Regimento interno" data="14/03/2019"
                 titulo="Capítulo IV — Animais" pagina={14} href="/documentos/regimento#p14">
      É permitida a permanência de <Destaque>animais domésticos</Destaque>…
    </TrechoFonte>
  }
>
  Sim, é permitido ter cachorro, desde que não comprometa segurança, higiene e sossego.
</RespostaSintetizada>
```

`fontes` é prop **obrigatória**: é impossível, por tipo, renderizar síntese sem citação (§4, §6.2).
A síntese fica em superfície apagada e sem sombra; o trecho fica em card branco — a hierarquia é
o inverso do padrão de chatbot, de propósito. `TrechoFonte` exige `pagina` e `href`: citação sem
página não é citação.

### `SeloProveniencia`

```tsx
<SeloProveniencia publicadoEm="12/09/2025" publicadoPor="Conselho fiscal"
                  natureza="oficial" fonte={{ href: "/doc/123", rotulo: "Ver documento original" }} />
```

Obrigatório em qualquer superfície que exiba número ou conteúdo publicado (§6.5).
`natureza`: `oficial` (documento) ou `auxiliar` (resumo — nunca substitui o texto oficial).

### `GraficoBarras` e `GraficoOrcadoRealizado`

Ver `docs/design/graficos.md`. Rótulo de valor é prop obrigatória; a ordenação decrescente é feita
dentro do componente.

---

## 7. Acessibilidade — como isso é verificado

| Regra | Onde é testada |
|---|---|
| Contraste dos tokens (AA/AAA) | `tests/unit/contraste-tokens.test.ts` — roda em `pnpm test` |
| Contraste renderizado, AA na página e AAA no financeiro | `tests/a11y/contraste.spec.ts` (axe) |
| Corpo ≥18px, nada abaixo de 16px, 200% sem rolagem horizontal, refluxo em 320px | `tests/a11y/escala-fonte.spec.ts` |
| Alvo de toque ≥48px | `tests/a11y/alvo-toque.spec.ts` |

```bash
pnpm install                          # traz @playwright/test e @axe-core/playwright
pnpm exec playwright install chromium
pnpm test                             # unitário, inclui contraste dos tokens
pnpm test:a11y                        # Playwright + axe sobre /design-system
```

Toda primitiva nova **entra em `/design-system`** — é o que os testes varrem. Primitiva fora da
vitrine é primitiva sem cobertura.

Outras regras que valem sem teste automatizado: foco visível nunca removido; link nunca
distinguido só por cor (sublinhado por padrão); `prefers-reduced-motion` respeitado globalmente;
heading em ordem, sem pular nível.

---

## 8. Decisões desta fase, abertas a contestação

1. **Sem modo escuro em F0.**
2. **`text-xs`/`text-sm` removidos do Tailwind.** Copiar componente do shadcn.com vai exigir
   trocar o tamanho de fonte à mão. É intencional.
3. **Sem `class-variance-authority`, `clsx`, `tailwind-merge` ou Radix.** Os seis primitivos desta
   fase são elementos nativos; `lib/cn.ts` resolve conflito de classe e `components/ui/slot.tsx`
   resolve `asChild`. Quando entrar um componente com comportamento real (combobox, diálogo,
   accordion do §6.3), aí sim vale trazer Radix — e `cn` pode virar `twMerge` numa linha.

### Já decidido, não reabrir

**Erro de formulário é vermelho** (`--color-erro`), com o prefixo "Erro:". Propus marrom-alerta
numa leitura literal do §6.6; o dono do projeto corrigiu a regra: o §6.6 proíbe vermelho e verde
**decorativos**, não semânticos. Quebrar a convenção universal de erro custa mais, num público
com baixa familiaridade digital, do que ganha em pureza de paleta. Decidido, fechado.

---

## 9. Invariantes travadas no tipo — não afrouxar

A regra que vale é a que o compilador cobra. Estas já existem e **não podem virar opcionais** por
conveniência de tela:

| Invariante | Onde | O que impede |
|---|---|---|
| `RespostaSintetizada` exige `fontes` | `components/ui/citacao.tsx` | síntese sem citação (§4, §6.2) |
| `TrechoFonte` exige `pagina` e `href` | idem | citação que não leva à fonte |
| `BadgeStatus` exige `children` textual | `components/ui/badge.tsx` | status comunicado só por cor |
| `ItemBarra.rotuloValor` obrigatório | `components/ui/barras.tsx` | barra sem rótulo direto (§6.4) |
| `Table` exige `rotulo` | `components/ui/table.tsx` | região rolável inacessível por teclado |
| `CampoTexto` exige `rotulo` | `components/ui/input.tsx` | campo rotulado só por placeholder |

Dois candidatos ainda não implementados, para quando o domínio chegar: **valor monetário que
aceite `number`** (tem que ser tipo de centavos, §2) e **componente de dado sem proveniência**
(§6.5). Quem construir o primeiro componente financeiro de F2 fecha esses dois.
