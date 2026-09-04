import * as React from "react";
import { cn } from "@/lib/cn";

/**
 * Card. Superfície branca sobre papel cinza-azulado; o limite vem da BORDA,
 * não da sombra (§6.6: sóbrio, sem efeito). Card branco sem borda é invisível
 * no papel — a borda é obrigatória, por isso está na base e não em variante.
 */

type Div = React.HTMLAttributes<HTMLDivElement>;

export function Card({ className, ...props }: Div) {
  return (
    <div
      data-slot="card"
      className={cn(
        "flex flex-col gap-4 rounded-lg border border-borda bg-superficie p-5 shadow-sm",
        className,
      )}
      {...props}
    />
  );
}

export function CardHeader({ className, ...props }: Div) {
  return (
    <div
      data-slot="card-header"
      className={cn("flex flex-col gap-1", className)}
      {...props}
    />
  );
}

export function CardTitle({
  className,
  as: Tag = "h2",
  ...props
}: React.HTMLAttributes<HTMLHeadingElement> & {
  as?: "h1" | "h2" | "h3" | "h4";
}) {
  return (
    <Tag
      data-slot="card-title"
      className={cn("text-xl font-semibold text-tinta", className)}
      {...props}
    />
  );
}

export function CardDescription({
  className,
  ...props
}: React.HTMLAttributes<HTMLParagraphElement>) {
  return (
    <p
      data-slot="card-description"
      className={cn("text-base text-tinta-suave", className)}
      {...props}
    />
  );
}

export function CardContent({ className, ...props }: Div) {
  return (
    <div
      data-slot="card-content"
      className={cn("flex flex-col gap-3", className)}
      {...props}
    />
  );
}

export function CardFooter({ className, ...props }: Div) {
  return (
    <div
      data-slot="card-footer"
      className={cn(
        "flex flex-wrap items-center gap-3 border-t border-borda pt-4",
        className,
      )}
      {...props}
    />
  );
}
