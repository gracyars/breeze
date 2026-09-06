import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";

import { Badge, Button, Card, CardContent, CardHeader, CardTitle } from "@/components/ui";
import { carregaDocumento, urlAssinadaDoOriginal } from "@/lib/acervo/documentos";

export const metadata: Metadata = { title: "Documento · Breeze" };

export default async function PaginaDoDocumento({
  params,
}: PageProps<"/acervo/[id]">) {
  const { id } = await params;
  const documento = await carregaDocumento(id);
  if (!documento) notFound();

  const urlOriginal = await urlAssinadaDoOriginal(id);

  return (
    <main className="mx-auto w-full max-w-4xl flex-1 px-4 py-10">
      <Link href="/acervo" className="text-base text-acao">
        ← Acervo
      </Link>

      <header className="mt-4 mb-8">
        <h1 className="text-2xl font-semibold text-tinta">{documento.titulo}</h1>
        <div className="mt-3 flex flex-wrap items-center gap-3 text-base text-tinta-suave">
          <Badge>{documento.tipo}</Badge>
          {documento.paginas && <span>{documento.paginas} páginas</span>}
          {documento.visibilidade === "publico" && <Badge>público</Badge>}
          {urlOriginal && (
            <Button asChild variante="secundaria" tamanho="compacta">
              <a href={urlOriginal} target="_blank" rel="noreferrer">
                Abrir o PDF original
              </a>
            </Button>
          )}
        </div>
        {urlOriginal && (
          <p className="mt-2 text-meta text-tinta-suave">
            O link do PDF vale por 5 minutos e é só seu — copiar e mandar para outra
            pessoa não funciona depois disso.
          </p>
        )}
      </header>

      {documento.status === "erro" && (
        <Card className="mb-6">
          <CardHeader>
            <CardTitle className="text-lg">Este documento precisa de atenção</CardTitle>
          </CardHeader>
          <CardContent>
            <p className="text-base text-tinta">{documento.erro_detalhe}</p>
          </CardContent>
        </Card>
      )}

      {documento.paginasTexto.length === 0 ? (
        <Card>
          <CardContent className="py-8">
            <p className="text-lg text-tinta">
              O texto deste documento ainda não foi lido.
            </p>
            <p className="mt-2 text-base text-tinta-suave">
              A leitura acontece em segundo plano, na máquina de quem administra o
              acervo. Volte daqui a pouco.
            </p>
          </CardContent>
        </Card>
      ) : (
        <ol className="space-y-6">
          {documento.paginasTexto.map((pagina) => (
            <li key={pagina.pagina}>
              <Card>
                <CardHeader className="pb-2">
                  <CardTitle className="text-lg">
                    Página {pagina.pagina}
                    {pagina.fonte_texto === "ocr" && (
                      <span className="ml-3 align-middle text-meta font-normal text-tinta-suave">
                        texto reconhecido por leitura de imagem
                        {pagina.confianca_ocr !== null &&
                          ` · confiança ${(pagina.confianca_ocr * 100).toFixed(0)}%`}
                      </span>
                    )}
                  </CardTitle>
                </CardHeader>
                <CardContent>
                  {pagina.texto ? (
                    <p className="whitespace-pre-wrap font-legal text-legal leading-relaxed text-tinta">
                      {pagina.texto}
                    </p>
                  ) : (
                    <p className="text-base text-tinta-suave">
                      Esta página não tem texto extraível — é imagem. Abra o PDF
                      original para lê-la.
                    </p>
                  )}
                </CardContent>
              </Card>
            </li>
          ))}
        </ol>
      )}
    </main>
  );
}
