"use client";

import * as React from "react";
import { cn } from "@/lib/cn";

/**
 * Campo de texto.
 *
 * - 48px de altura e 18px de texto: dedo e vista de morador idoso (§6.5).
 * - Borda `borda-forte` (3,3:1 no papel) — WCAG 1.4.11 exige limite perceptível
 *   em controle de formulário; borda hairline decorativa não serve aqui.
 * - Erro em vermelho (`--color-erro`, AAA) MAIS o prefixo literal "Erro:".
 *   O §6.6 proíbe vermelho decorativo, não vermelho semântico: aqui a cor
 *   carrega significado e é convenção universal — quebrá-la custa caro num
 *   público com baixa familiaridade digital. O texto continua sendo o que
 *   sustenta a leitura de quem não distingue a cor.
 */

const BASE =
  "block w-full alvo-toque rounded-md border-2 border-borda-forte bg-superficie " +
  "px-4 py-2 text-base text-tinta placeholder:text-tinta-fraca " +
  "disabled:bg-superficie-muda disabled:text-tinta-suave " +
  "aria-[invalid=true]:border-erro";

export type InputProps = React.InputHTMLAttributes<HTMLInputElement>;

export function Input({ className, ...props }: InputProps) {
  return <input data-slot="input" className={cn(BASE, className)} {...props} />;
}

export type CampoTextoProps = InputProps & {
  /** Rótulo visível. Nunca usar só placeholder como rótulo. */
  rotulo: string;
  /** Texto de apoio permanente (formato esperado, exemplo). */
  ajuda?: string;
  /** Mensagem de erro. Presente => campo marcado como inválido. */
  erro?: string;
};

export function CampoTexto({
  rotulo,
  ajuda,
  erro,
  id,
  className,
  ...props
}: CampoTextoProps) {
  const gerado = React.useId();
  const idCampo = id ?? gerado;
  const idAjuda = `${idCampo}-ajuda`;
  const idErro = `${idCampo}-erro`;

  const descrito =
    [ajuda ? idAjuda : null, erro ? idErro : null].filter(Boolean).join(" ") ||
    undefined;

  return (
    <div className="flex flex-col gap-2" data-slot="campo-texto">
      <label htmlFor={idCampo} className="text-base font-semibold text-tinta">
        {rotulo}
      </label>

      {ajuda ? (
        <p id={idAjuda} className="text-meta text-tinta-suave">
          {ajuda}
        </p>
      ) : null}

      <Input
        id={idCampo}
        aria-invalid={erro ? true : undefined}
        aria-describedby={descrito}
        className={className}
        {...props}
      />

      {erro ? (
        <p id={idErro} className="text-meta font-semibold text-erro">
          <span className="font-bold">Erro:</span> {erro}
        </p>
      ) : null}
    </div>
  );
}
