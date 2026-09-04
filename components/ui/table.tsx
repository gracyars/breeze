import * as React from "react";
import { cn } from "@/lib/cn";

/**
 * Tabela de dado financeiro.
 *
 * - Rolagem horizontal é `role="region"` com `tabIndex={0}`: tabela larga tem
 *   que ser alcançável por teclado (WCAG 2.1.1). Exceção legítima ao refluxo
 *   de 320px (1.4.10 permite conteúdo bidimensional).
 * - Coluna de valor usa `numerico`: algarismo tabular, alinhado à direita.
 *   Sem isso a coluna não alinha e o conselho perde a leitura vertical.
 * - Zebra por linha: ajuda a não pular de linha em tela pequena e em 200%.
 */

export function Table({
  className,
  rotulo,
  children,
  ...props
}: React.TableHTMLAttributes<HTMLTableElement> & { rotulo: string }) {
  return (
    <div
      role="region"
      aria-label={rotulo}
      tabIndex={0}
      className="w-full overflow-x-auto rounded-lg border border-borda-forte bg-superficie"
    >
      <table
        data-slot="table"
        className={cn("w-full border-collapse text-base", className)}
        {...props}
      >
        {children}
      </table>
    </div>
  );
}

export function TableCaption({
  className,
  ...props
}: React.HTMLAttributes<HTMLTableCaptionElement>) {
  return (
    <caption
      data-slot="table-caption"
      className={cn(
        "caption-top border-b border-borda px-4 py-3 text-left text-base font-semibold text-tinta",
        className,
      )}
      {...props}
    />
  );
}

export function TableHeader({
  className,
  ...props
}: React.HTMLAttributes<HTMLTableSectionElement>) {
  return (
    <thead
      data-slot="table-header"
      className={cn("bg-superficie-alt", className)}
      {...props}
    />
  );
}

export function TableBody({
  className,
  ...props
}: React.HTMLAttributes<HTMLTableSectionElement>) {
  return <tbody data-slot="table-body" className={cn(className)} {...props} />;
}

export function TableFooter({
  className,
  ...props
}: React.HTMLAttributes<HTMLTableSectionElement>) {
  return (
    <tfoot
      data-slot="table-footer"
      className={cn(
        "border-t-2 border-borda-forte bg-superficie-alt font-semibold",
        className,
      )}
      {...props}
    />
  );
}

export function TableRow({
  className,
  ...props
}: React.HTMLAttributes<HTMLTableRowElement>) {
  return (
    <tr
      data-slot="table-row"
      className={cn(
        "border-b border-borda last:border-b-0 even:bg-superficie-alt",
        className,
      )}
      {...props}
    />
  );
}

/** Valor monetário ou quantidade: tabular, à direita. */
type Numerico = { numerico?: boolean };

type CabecalhoProps = React.ThHTMLAttributes<HTMLTableCellElement> & Numerico;
type CelulaProps = React.TdHTMLAttributes<HTMLTableCellElement> & Numerico;

export function TableHead({ className, numerico, ...props }: CabecalhoProps) {
  return (
    <th
      data-slot="table-head"
      scope={props.scope ?? "col"}
      className={cn(
        "px-4 py-3 text-left align-middle text-meta font-semibold uppercase tracking-wide text-tinta-suave",
        numerico && "text-right",
        className,
      )}
      {...props}
    />
  );
}

export function TableCell({ className, numerico, ...props }: CelulaProps) {
  return (
    <td
      data-slot="table-cell"
      className={cn(
        "px-4 py-3 align-middle text-base text-tinta",
        numerico && "numero text-right font-medium",
        className,
      )}
      {...props}
    />
  );
}
