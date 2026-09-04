import * as React from "react";
import { cn } from "@/lib/cn";

/**
 * Badge. Sempre com TEXTO — nunca só cor, nunca só ícone (WCAG 1.4.1 e §6.5:
 * o público não infere significado por cor). Tamanho mínimo 16px.
 */

// Sem `whitespace-nowrap`: em 320px com fonte a 200%, "acima do orçamento"
// precisa poder quebrar em vez de empurrar a página para o lado.
const BASE =
  "inline-flex items-center gap-1.5 rounded-sm border px-2.5 py-1 " +
  "text-meta font-semibold";

const VARIANTES = {
  /** Tipo de documento, competência, faceta. */
  neutro: "border-borda-forte bg-superficie-alt text-tinta",
  /** Marca de contexto ligada a ação/navegação. */
  acao: "border-acao bg-acao-suave text-acao",
  /** Rascunho x publicado (§6.1): rascunho jamais parece publicado. */
  rascunho: "border-borda-forte bg-superficie-muda text-tinta-suave uppercase tracking-wide",
} as const;

export type BadgeProps = React.HTMLAttributes<HTMLSpanElement> & {
  variante?: keyof typeof VARIANTES;
};

export function Badge({ className, variante = "neutro", ...props }: BadgeProps) {
  return (
    <span
      data-slot="badge"
      className={cn(BASE, VARIANTES[variante], className)}
      {...props}
    />
  );
}

/* -------------------------------------------------------------------------- */

/**
 * Badge de status financeiro — ÚNICO lugar do sistema onde verde e vermelho
 * podem aparecer (§6.6). Contraste AAA em todos os tons (texto financeiro).
 * O glifo é redundância para daltonismo, não a informação: a palavra é.
 */
const STATUS = {
  positivo: {
    classe: "border-positivo bg-positivo-suave text-positivo",
    glifo: "▲",
  },
  negativo: {
    classe: "border-negativo bg-negativo-suave text-negativo",
    glifo: "▼",
  },
  atencao: {
    classe: "border-atencao bg-atencao-suave text-atencao",
    glifo: "!",
  },
  neutro: {
    classe: "border-borda-forte bg-superficie-alt text-tinta",
    glifo: "•",
  },
} as const;

export type BadgeStatusProps = React.HTMLAttributes<HTMLSpanElement> & {
  status: keyof typeof STATUS;
  /** Texto obrigatório: "dentro do orçamento", "acima do orçamento", "em aberto". */
  children: React.ReactNode;
  /** Desliga o glifo quando já existe outro indicador não-cromático ao lado. */
  semGlifo?: boolean;
};

export function BadgeStatus({
  className,
  status,
  semGlifo = false,
  children,
  ...props
}: BadgeStatusProps) {
  const { classe, glifo } = STATUS[status];
  return (
    <span
      data-slot="badge-status"
      data-status={status}
      className={cn(BASE, classe, className)}
      {...props}
    >
      {semGlifo ? null : (
        <span aria-hidden="true" className="leading-none">
          {glifo}
        </span>
      )}
      {children}
    </span>
  );
}
