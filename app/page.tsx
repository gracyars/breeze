import Link from "next/link";

import { Button, Card, CardContent, CardHeader, CardTitle } from "@/components/ui";
import { sessaoAtual } from "@/lib/supabase/servidor";

/**
 * Entrada do produto.
 *
 * A pergunta que o morador tem quando abre isto não é "que sistema é este?", é
 * "posso ter cachorro?" / "por que a cota subiu?". Por isso a busca é o primeiro
 * elemento, e não um painel de boas-vindas.
 */
export default async function Home() {
  const sessao = await sessaoAtual();

  return (
    <main className="mx-auto flex w-full max-w-3xl flex-1 flex-col justify-center px-4 py-12">
      <h1 className="text-3xl font-semibold text-tinta">Breeze Bosque da Saúde</h1>
      <p className="mt-3 text-lg text-tinta-suave">
        Os documentos e as contas do condomínio, com a fonte de cada número.
      </p>

      <div className="mt-8 flex flex-wrap gap-3">
        <Button asChild tamanho="lg">
          <Link href="/buscar">Buscar no acervo</Link>
        </Button>
        <Button asChild variante="secundaria" tamanho="lg">
          <Link href={sessao ? "/acervo" : "/entrar"}>
            {sessao ? "Ver o acervo" : "Entrar"}
          </Link>
        </Button>
      </div>

      <Card className="mt-10">
        <CardHeader>
          <CardTitle className="text-lg">O que dá para fazer hoje</CardTitle>
        </CardHeader>
        <CardContent className="space-y-2 text-base text-tinta">
          <p>
            Procurar por palavra nos documentos do condomínio e ler o trecho exato,
            com o documento e a página de onde ele saiu.
          </p>
          <p className="text-tinta-suave">
            Em construção: perguntas em linguagem natural, o painel financeiro e os
            alertas de fiscalização. Cada coisa entra depois de a anterior estar em
            uso de verdade.
          </p>
        </CardContent>
      </Card>
    </main>
  );
}
