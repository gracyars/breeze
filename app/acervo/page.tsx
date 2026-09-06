import type { Metadata } from "next";
import Link from "next/link";

import { Badge, Button, Card, CardContent, CardHeader, CardTitle } from "@/components/ui";
import { listaDocumentos } from "@/lib/acervo/documentos";

export const metadata: Metadata = {
  title: "Acervo · Breeze",
  description: "Documentos do condomínio, com a fonte de cada um.",
};

const ROTULO_DE_STATUS: Record<string, { texto: string; tom: "neutro" | "atencao" | "ok" }> = {
  pendente: { texto: "aguardando arquivo", tom: "neutro" },
  processando: { texto: "lendo o documento", tom: "neutro" },
  indexado: { texto: "pronto para revisão", tom: "neutro" },
  em_revisao: { texto: "aguardando conferência", tom: "atencao" },
  publicado: { texto: "publicado", tom: "ok" },
  erro: { texto: "precisa de atenção", tom: "atencao" },
};

export default async function PaginaDoAcervo() {
  const documentos = await listaDocumentos();

  return (
    <main className="mx-auto w-full max-w-4xl flex-1 px-4 py-10">
      <div className="mb-8 flex items-center justify-between gap-4">
        <h1 className="text-2xl font-semibold text-tinta">Acervo</h1>
        <Button asChild variante="secundaria">
          <Link href="/acervo/enviar">Enviar documento</Link>
        </Button>
      </div>

      {documentos.length === 0 ? (
        <Card>
          <CardContent className="py-8">
            <p className="text-lg text-tinta">Ainda não há documento no acervo.</p>
            <p className="mt-2 text-base text-tinta-suave">
              Documento enviado passa por leitura automática e depois por conferência
              sua — nada aparece para os moradores antes disso.
            </p>
          </CardContent>
        </Card>
      ) : (
        <ul className="space-y-3">
          {documentos.map((documento) => {
            const rotulo = ROTULO_DE_STATUS[documento.status] ?? {
              texto: documento.status,
              tom: "neutro" as const,
            };
            return (
              <li key={documento.id}>
                <Card>
                  <CardHeader className="pb-2">
                    <CardTitle className="text-lg">
                      <Link href={`/acervo/${documento.id}`} className="text-acao">
                        {documento.titulo}
                      </Link>
                    </CardTitle>
                  </CardHeader>
                  <CardContent className="flex flex-wrap items-center gap-3 text-base text-tinta-suave">
                    <Badge>{documento.tipo}</Badge>
                    <span>{documento.paginas ? `${documento.paginas} páginas` : "—"}</span>
                    <span>{rotulo.texto}</span>
                    {documento.visibilidade === "publico" && <Badge>público</Badge>}
                  </CardContent>
                </Card>
              </li>
            );
          })}
        </ul>
      )}

      <p className="mt-8 text-base text-tinta-suave">
        Você vê aqui o que o seu papel permite ver. A lista é filtrada pelo banco de
        dados, não pela tela.
      </p>
    </main>
  );
}
