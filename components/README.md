# components/

Componentes de UI. `components/ui/` são os primitivos do design system: botão, campo, card,
badge, tabela, par de citação e os dois gráficos permitidos. Importe pelo barril
(`@/components/ui`), não pelo caminho do arquivo.

Regras de uso, tabela de contraste e o que é proibido: **`docs/design-system.md`**.
Regras de gráfico: **`docs/design/graficos.md`**.

Componente de feature **não** entra aqui e **não** redefine token, cor ou tamanho de fonte.
Primitiva nova precisa entrar em `app/design-system/page.tsx` — é a superfície que os testes de
acessibilidade (`tests/a11y/`) varrem.
