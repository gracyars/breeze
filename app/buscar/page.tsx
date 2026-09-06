import type { Metadata } from "next";
import Link from "next/link";

import { Badge, Button, Card, CardContent, Input } from "@/components/ui";
import { busca, referencia } from "@/lib/busca/buscar";

export const metadata: Metadata = {
  title: "Buscar · Breeze",
  description: "Busca no acervo do condomínio, com a fonte de cada resposta.",
};

const SUGESTOES = [
  "posso ter cachorro?",
  "quem paga o conserto do portão",
  "horário do salão de festas",
  "AGE de fevereiro",
];

export default async function PaginaDeBusca({
  searchParams,
}: PageProps<"/buscar">) {
  const { q } = await searchParams;
  const consulta = typeof q === "string" ? q.trim() : "";
  const resposta = consulta ? await busca(consulta) : null;

  return (
    <main className="mx-auto w-full max-w-3xl flex-1 px-4 py-10">
      <h1 className="mb-6 text-2xl font-semibold text-tinta">Buscar no acervo</h1>

      <form action="/buscar" method="get" className="flex flex-wrap gap-3">
        <Input
          name="q"
          defaultValue={consulta}
          aria-label="O que você quer saber"
          placeholder={SUGESTOES[0]}
          className="flex-1 min-w-64"
        />
        <Button type="submit">Buscar</Button>
      </form>

      {!resposta && (
        <div className="mt-8 space-y-3">
          <p className="text-base text-tinta-suave">Experimente:</p>
          <ul className="flex flex-wrap gap-2">
            {SUGESTOES.map((sugestao) => (
              <li key={sugestao}>
                <Link
                  href={`/buscar?q=${encodeURIComponent(sugestao)}`}
                  className="inline-block rounded-md border-2 border-borda-forte px-3 py-2 text-base text-acao no-underline"
                >
                  {sugestao}
                </Link>
              </li>
            ))}
          </ul>
        </div>
      )}

      {resposta && (
        <>
          {/*
            Aviso obrigatório enquanto a metade semântica está desligada (D18).
            Acervo que responde pela metade sem dizer é pior que acervo que diz:
            quem não sabe da limitação conclui que a resposta não existe.
          */}
          {!resposta.metadeSemanticaLigada && (
            <p className="mt-6 rounded-md border-2 border-borda-forte px-4 py-3 text-base text-tinta">
              Esta busca encontra <strong>as palavras que você digitou</strong> (e os
              sinônimos que conhecemos), ainda não o sentido da pergunta. Se não achar,
              tente as palavras que o documento usaria — &quot;cota&quot; em vez de
              &quot;taxa&quot;, por exemplo.
            </p>
          )}

          <p className="mt-6 text-base text-tinta-suave">
            {resposta.resultados.length === 0
              ? "Nenhum trecho encontrado."
              : `${resposta.resultados.length} trecho(s) encontrado(s).`}
          </p>

          {resposta.resultados.length === 0 && (
            <Card className="mt-4">
              <CardContent className="py-6">
                <p className="text-base text-tinta">
                  O acervo não respondeu a essa pergunta. Isso pode significar que o
                  documento ainda não foi enviado, ou que ele usa outras palavras.
                </p>
                <p className="mt-2 text-base text-tinta-suave">
                  Preferimos dizer que não achamos a inventar uma resposta.
                </p>
              </CardContent>
            </Card>
          )}

          <ol className="mt-4 space-y-4">
            {resposta.resultados.map((resultado) => (
              <li key={resultado.chunkId}>
                <Card>
                  <CardContent className="py-5">
                    {/*
                      O trecho literal é o resultado primário — o inverso do padrão
                      de chatbot (SPEC §4). A síntese, quando existir, vem depois e
                      sempre com esta citação do lado.

                      O HTML aqui vem de `ts_headline`, e a função no banco escapa
                      `&` e `<` do texto ANTES de marcar os termos. Sem esse escape
                      um PDF com `<script>` dentro viraria injeção na tela de quem
                      busca — o acervo é conteúdo de terceiro, não é nosso.
                    */}
                    <p
                      className="font-legal text-legal leading-relaxed text-tinta [&_mark]:bg-acao-suave [&_mark]:font-semibold"
                      dangerouslySetInnerHTML={{ __html: resultado.trecho }}
                    />
                    <p className="mt-3 flex flex-wrap items-center gap-2 text-base text-tinta-suave">
                      <Badge>{resultado.tipo}</Badge>
                      <Link
                        href={`/acervo/${resultado.documentoId}`}
                        className="text-acao"
                      >
                        {referencia(resultado)}
                      </Link>
                    </p>

                    {/*
                      O mesmo texto costuma estar em dois lugares: a ata que
                      aprovou o regimento anexa o regimento inteiro. Mostrar as
                      duas cópias como resultados diferentes faria o morador achar
                      que são regras diferentes — então o normativo fica, e a
                      cópia vira esta nota, que é útil numa assembleia.
                    */}
                    {resultado.tambemEm.length > 0 && (
                      <p className="mt-2 text-meta text-tinta-suave">
                        O mesmo texto aparece também em{" "}
                        {resultado.tambemEm.map((outro, indice) => (
                          <span key={outro.documentoId}>
                            {indice > 0 && ", "}
                            <Link href={`/acervo/${outro.documentoId}`} className="text-acao">
                              {outro.titulo}
                            </Link>
                          </span>
                        ))}
                        .
                      </p>
                    )}
                  </CardContent>
                </Card>
              </li>
            ))}
          </ol>
        </>
      )}
    </main>
  );
}
