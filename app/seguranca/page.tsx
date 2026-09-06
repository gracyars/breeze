import type { Metadata } from "next";
import { redirect } from "next/navigation";

import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui";
import { clienteDoServidor, sessaoAtual } from "@/lib/supabase/servidor";

import { PainelDeSeguranca } from "./painel";

export const metadata: Metadata = {
  title: "Segundo fator · Breeze",
};

export default async function PaginaDeSeguranca() {
  const sessao = await sessaoAtual();
  if (!sessao) redirect("/entrar?proximo=/seguranca");

  const supabase = await clienteDoServidor();
  const { data } = await supabase.auth.mfa.listFactors();
  const verificado = data?.totp?.find((fator) => fator.status === "verified") ?? null;

  return (
    <main className="mx-auto flex w-full max-w-xl flex-1 flex-col justify-center px-4 py-12">
      <Card>
        <CardHeader>
          <CardTitle>Segundo fator</CardTitle>
          <CardDescription>
            Entrou como {sessao.email ?? "sua conta"}. Nível desta sessão:{" "}
            {sessao.aal === "aal2" ? "verificado" : "só o primeiro fator"}.
          </CardDescription>
        </CardHeader>
        <CardContent>
          <PainelDeSeguranca
            aal={sessao.aal}
            fatorVerificado={verificado ? { id: verificado.id } : null}
          />
        </CardContent>
      </Card>
    </main>
  );
}
