import * as React from "react";
import { cn } from "@/lib/cn";

/**
 * Slot mínimo (substituto local de `@radix-ui/react-slot`).
 * Permite `asChild`: o componente empresta estilo e semântica ao filho —
 * necessário para `<Button asChild><Link/></Button>` sem aninhar <a> em <button>.
 */
export function Slot({
  children,
  ...props
}: React.HTMLAttributes<HTMLElement> & { children: React.ReactNode }) {
  if (!React.isValidElement(children)) return null;

  const filho = children as React.ReactElement<Record<string, unknown>>;
  const propsFilho = filho.props;

  return React.cloneElement(filho, {
    ...props,
    ...propsFilho,
    className: cn(
      props.className as string | undefined,
      propsFilho.className as string | undefined,
    ),
    style: {
      ...(props.style as React.CSSProperties | undefined),
      ...(propsFilho.style as React.CSSProperties | undefined),
    },
  });
}
