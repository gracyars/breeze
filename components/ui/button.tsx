import * as React from "react";
import { cn } from "@/lib/cn";
import { Slot } from "./slot";

/**
 * Botão. SPEC §6.5: verbo claro ("Ver boleto", nunca "Acessar módulo financeiro"),
 * alvo ≥48px em qualquer tamanho, foco visível.
 *
 * Não existe variante vermelha de "ação destrutiva": vermelho é reservado a
 * status financeiro (§6.6). Ação destrutiva usa `secundaria` + confirmação
 * explícita em texto.
 */

// `no-underline`: quando o botão empresta o estilo a um <a> (asChild), a forma
// de botão já o distingue; o sublinhado global de link vira ruído aqui.
const BASE =
  "inline-flex items-center justify-center gap-2 rounded-md font-semibold no-underline " +
  "transition-colors duration-150 " +
  "disabled:pointer-events-none disabled:bg-superficie-muda disabled:text-tinta-suave " +
  "disabled:border-borda-forte";

const VARIANTES = {
  /** Ação principal da tela. Uma por tela. */
  primaria:
    "bg-acao text-white border-2 border-acao hover:bg-acao-forte hover:border-acao-forte active:bg-acao-ativa",
  /** Ação secundária, e também toda ação destrutiva (nunca vermelha). */
  secundaria:
    "bg-superficie text-acao border-2 border-acao hover:bg-acao-suave active:bg-acao-suave",
  /** Ação terciária em barra de ferramentas e lista. */
  discreta:
    "bg-transparent text-acao border-2 border-transparent hover:bg-acao-suave active:bg-acao-suave",
} as const;

const TAMANHOS = {
  /** Padrão: 48px de altura, 18px de texto. */
  md: "alvo-toque px-5 text-base",
  /** CTA principal no celular: 56px. */
  lg: "alvo-toque-lg px-6 text-lg",
  /** Menos respiro lateral, MESMA altura mínima. Nunca reduzir abaixo de 48px. */
  compacta: "alvo-toque px-3 text-base",
} as const;

export type ButtonProps = React.ButtonHTMLAttributes<HTMLButtonElement> & {
  variante?: keyof typeof VARIANTES;
  tamanho?: keyof typeof TAMANHOS;
  /** Empresta o estilo ao filho (ex.: next/link) em vez de renderizar <button>. */
  asChild?: boolean;
};

export function Button({
  className,
  variante = "primaria",
  tamanho = "md",
  asChild = false,
  type = "button",
  ...props
}: ButtonProps) {
  const classes = cn(BASE, VARIANTES[variante], TAMANHOS[tamanho], className);

  if (asChild) {
    return (
      <Slot className={classes} data-slot="button">
        {props.children}
      </Slot>
    );
  }

  return <button type={type} data-slot="button" className={classes} {...props} />;
}
