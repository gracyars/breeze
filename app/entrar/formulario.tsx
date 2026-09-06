"use client";

import { useActionState } from "react";

import { Button, CampoTexto } from "@/components/ui";

import { iniciarEntrada, type EstadoDeEntrada } from "./acoes";

const INICIAL: EstadoDeEntrada = { enviado: false, mensagem: "" };

/**
 * Formulário de entrada.
 *
 * Um campo só, aceitando CPF ou e-mail, porque o morador não deve precisar
 * lembrar qual dos dois cadastrou. A tela **não** valida CPF antes de enviar:
 * dizer "CPF inválido" já é responder diferente, e a resposta tem de ser a mesma
 * para tudo (ADR-0003).
 */
export function FormularioDeEntrada() {
  const [estado, acao, enviando] = useActionState(iniciarEntrada, INICIAL);

  if (estado.enviado) {
    return (
      <div className="space-y-4" role="status" aria-live="polite">
        <p className="text-lg text-tinta">{estado.mensagem}</p>
        <p className="text-base text-tinta-suave">
          O link vale por pouco tempo e só pode ser usado uma vez. Se não chegar em
          alguns minutos, tente de novo.
        </p>
      </div>
    );
  }

  return (
    <form action={acao} className="space-y-6">
      <CampoTexto
        rotulo="CPF ou e-mail"
        ajuda="Digite o CPF (só números) ou o e-mail cadastrado no condomínio."
        name="identificador"
        autoComplete="username"
        inputMode="text"
        required
      />
      <Button type="submit" tamanho="lg" disabled={enviando} className="w-full">
        {enviando ? "Enviando…" : "Receber link de acesso"}
      </Button>
      <p className="text-base text-tinta-suave">
        Não há senha. Você recebe um link no e-mail cadastrado e entra por ele.
      </p>
    </form>
  );
}
