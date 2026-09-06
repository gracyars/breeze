import type { Metadata } from "next";

import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui";

import { FormularioDeEntrada } from "./formulario";

export const metadata: Metadata = {
  title: "Entrar · Breeze",
  description: "Acesso do morador ao acervo e às contas do condomínio.",
};

export default function PaginaDeEntrada() {
  return (
    <main className="mx-auto flex w-full max-w-xl flex-1 flex-col justify-center px-4 py-12">
      <Card>
        <CardHeader>
          <CardTitle>Entrar no Breeze</CardTitle>
          <CardDescription>
            Documentos, contas e a fonte de cada número do Breeze Bosque da Saúde.
          </CardDescription>
        </CardHeader>
        <CardContent>
          <FormularioDeEntrada />
        </CardContent>
      </Card>
    </main>
  );
}
