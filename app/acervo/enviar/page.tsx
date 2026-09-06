import type { Metadata } from "next";
import { redirect } from "next/navigation";

import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui";
import { clienteDoServidor, sessaoAtual } from "@/lib/supabase/servidor";

import { FormularioDeEnvio } from "./formulario";

export const metadata: Metadata = { title: "Enviar documento · Breeze" };

export default async function PaginaDeEnvio() {
  const sessao = await sessaoAtual();
  if (!sessao) redirect("/entrar?proximo=/acervo/enviar");

  const supabase = await clienteDoServidor();
  const { data: tipos } = await supabase
    .from("tipos_documento")
    .select("codigo, nome")
    .order("ordem");

  return (
    <main className="mx-auto w-full max-w-xl flex-1 px-4 py-10">
      <Card>
        <CardHeader>
          <CardTitle>Enviar documento</CardTitle>
          <CardDescription>
            O documento entra no acervo para leitura automática e fica aguardando a
            sua conferência. Nada aparece para os moradores antes de você publicar.
          </CardDescription>
        </CardHeader>
        <CardContent>
          {sessao.aal !== "aal2" && (
            <p className="mb-6 text-base text-tinta">
              Publicar no acervo exige o segundo fator nesta sessão.{" "}
              <a href="/seguranca" className="text-acao">
                Verificar agora
              </a>
              .
            </p>
          )}
          <FormularioDeEnvio tipos={tipos ?? []} />
        </CardContent>
      </Card>
    </main>
  );
}
