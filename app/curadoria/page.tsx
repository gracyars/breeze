import type { Metadata } from "next";
import Link from "next/link";
import { redirect } from "next/navigation";

import { Card, CardContent } from "@/components/ui";
import { filaDeConferencia, progresso } from "@/lib/acervo/curadoria";
import { carregaDocumento } from "@/lib/acervo/documentos";
import { sessaoAtual } from "@/lib/supabase/servidor";

import { PainelDeConferencia } from "./painel";

export const metadata: Metadata = { title: "Conferência · Breeze" };

export default async function PaginaDeCuradoria({
  searchParams,
}: PageProps<"/curadoria">) {
  const sessao = await sessaoAtual();
  if (!sessao) redirect("/entrar?proximo=/curadoria");

  const { i } = await searchParams;
  const indice = Math.max(0, Number(typeof i === "string" ? i : 0) || 0);

  const [fila, conta] = await Promise.all([filaDeConferencia(), progresso()]);
  const item = fila[indice];

  return (
    <main className="mx-auto w-full max-w-3xl flex-1 px-4 py-10">
      <h1 className="mb-2 text-2xl font-semibold text-tinta">Conferência</h1>
      <p className="mb-8 text-base text-tinta-suave">
        {conta.publicados} de {conta.total} documento(s) publicado(s).
      </p>

      {sessao.aal !== "aal2" && (
        <p className="mb-6 text-base text-tinta">
          Publicar exige o segundo fator nesta sessão.{" "}
          <Link href="/seguranca" className="text-acao">
            Verificar agora
          </Link>
          .
        </p>
      )}

      {!item ? (
        <Card>
          <CardContent className="py-8">
            <p className="text-lg text-tinta">
              {fila.length === 0
                ? "Nada esperando conferência."
                : "Você chegou ao fim da fila."}
            </p>
            <p className="mt-2 text-base text-tinta-suave">
              {fila.length === 0 ? (
                <>
                  Documento enviado aparece aqui depois que o worker lê o texto.{" "}
                  <Link href="/acervo/enviar" className="text-acao">
                    Enviar documento
                  </Link>
                  .
                </>
              ) : (
                <Link href="/curadoria" className="text-acao">
                  Voltar ao começo
                </Link>
              )}
            </p>
          </CardContent>
        </Card>
      ) : (
        <PainelDeConferencia
          item={item}
          posicao={indice + 1}
          total={fila.length}
          temProximo={indice + 1 < fila.length}
          primeirasLinhas={await primeirasLinhasDe(item.id)}
        />
      )}
    </main>
  );
}

/**
 * As primeiras linhas do texto lido.
 *
 * A conferência precisa de uma amostra que responda "o texto bate com o
 * documento?" sem obrigar a abrir o PDF a cada item. Se a extração saiu torta,
 * aparece aqui, no primeiro olhar.
 */
async function primeirasLinhasDe(documentoId: string): Promise<string[]> {
  const documento = await carregaDocumento(documentoId);
  const primeira = documento?.paginasTexto.find((p) => p.texto);
  return (primeira?.texto ?? "").split("\n").slice(0, 8);
}
