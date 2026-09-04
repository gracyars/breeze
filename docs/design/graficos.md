# Breeze — Regras de gráfico

Normativo. Vale para todo gráfico do produto, em qualquer tela.
Base: SPEC §6.4 (financeiro para leigos) e §6.5 (acessibilidade); público do briefing §3.

## A regra que governa todas as outras

**O valor tem que estar escrito ao lado do dado.** Legenda não conta. Tooltip não conta. Eixo com
marcação não conta. O público-alvo não infere valor por comprimento nem por cor — e tooltip não
existe em toque, não existe para leitor de tela e não existe em impressão.

Se o gráfico só faz sentido com legenda, ele está errado. Se ele faz sentido sem o desenho, ótimo:
o desenho é reforço, o texto é a informação.

## Proibido

| O quê | Por quê |
|---|---|
| Pizza e rosca | Comparação por ângulo é o pior canal perceptivo; com 8+ contas do plano (§5.2) vira ilegível; rótulo não cabe. |
| Séries sobrepostas / área empilhada | Só a série de baixo tem linha de base comum; o resto vira estimativa. |
| Gráfico sem rótulo direto no elemento | Ver regra acima. |
| Cor como única codificação | 8% dos homens têm deficiência de visão de cor; verde/vermelho escuros se fundem. |
| Verde/vermelho sem significado | §6.6 proíbe a cor decorativa. Categoria de despesa **não** é status: usa o azul de ação. Verde e vermelho no gráfico só no veredito ("dentro"/"acima"), com a palavra ao lado. |
| Eixo de valor que não começa em zero | Em barra, exagera diferença. É distorção, e o produto é de fiscalização. |
| Animação de entrada, 3D, sombra, gradiente | §6.6. |

## Permitido

### 1. Número único do mês (§6.4, camada 1)

`text-4xl` + `numero` + selo de proveniência. Não é gráfico — e é a primeira coisa que o morador vê.

### 2. Barras horizontais ordenadas — "para onde foi o dinheiro" (camada 2)

`GraficoBarras` de `components/ui/barras.tsx`.

- Sempre ordenado do maior para o menor. O componente ordena sozinho; não passe pré-ordenado
  esperando outra ordem.
- Uma cor só (`--color-grafico-realizado`). Categoria é identificada pelo **nome escrito**, não
  pela cor: paleta categórica aqui é ruído.
- Cada linha traz nome + valor formatado (+ % opcional) em texto, acima da barra. `rotuloValor`
  é obrigatório na prop.
- Barra é `aria-hidden`: o leitor de tela já leu nome e valor: repetir seria ruído.
- Barra clara leva contorno de 1px (`--color-grafico-contorno`, 5,2:1) — WCAG 1.4.11.
- Cada categoria é clicável até o lançamento e daí até o comprovante (§6.4): passe `href`.
- Horizontal, não vertical: nome de conta condominial é longo ("Água, energia e gás") e em barra
  vertical o rótulo gira 90° ou some.

```tsx
<GraficoBarras
  titulo="Despesas de agosto de 2025"
  itens={[{ rotulo: "Elevadores", valor: 4320, rotuloValor: "R$ 4.320,00",
            rotuloPercentual: "6%", href: "/financeiro/conta/elevadores" }]}
/>
```

### 3. Barras pareadas — orçado × realizado (camada 3)

`GraficoOrcadoRealizado`.

- Duas barras **empilhadas verticalmente** por categoria, nunca sobrepostas, nunca uma barra só
  dividida.
- Cada barra tem prefixo textual próprio ("Orçado", "Realizado") e o valor formatado. Ninguém
  precisa consultar legenda para saber qual é qual.
- Escala comum entre as duas barras da mesma categoria — senão a comparação mente.
- Veredito em `BadgeStatus` com palavra: "dentro do orçamento" / "acima do orçamento". É aqui,
  e só aqui na tela de gráfico, que verde e vermelho aparecem.
- Cinza claro (orçado) vs azul profundo (realizado): a diferença de luminância sobrevive à
  impressão em preto e branco e ao daltonismo.

### 4. Série histórica

Ainda **não implementada** (entra com F2). Quando entrar, a regra é: linha única por vez, um ponto
por competência, rótulo de valor no primeiro, no último e nos extremos; jamais 6 linhas juntas —
prefira repetição de gráfico pequeno (small multiples), um por conta, cada um com seu rótulo.

## Formatação de valor

Formatação é domínio, não design system: os componentes recebem a string já pronta
(`rotuloValor`). Convenções esperadas de quem chama: `R$ 1.234,56`, pt-BR, valor vindo de
`bigint` em centavos (§2), sempre com o selo de proveniência por perto (§6.5).

## Checklist antes de aprovar qualquer gráfico

- [ ] O valor está escrito, em texto, junto de cada elemento?
- [ ] O gráfico continua compreensível impresso em preto e branco?
- [ ] Continua compreensível com o CSS desligado (ou seja: o texto sozinho conta a história)?
- [ ] Nenhuma pizza, nenhuma série sobreposta, eixo começando em zero?
- [ ] Verde/vermelho só onde carregam significado, sempre com a palavra ao lado?
- [ ] Tudo clicável tem 48px?
- [ ] A 200% de fonte, ainda cabe sem rolagem horizontal na página?
