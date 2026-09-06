"use client";

import Link from "next/link";
import { useActionState } from "react";

import { Badge, Button, Card, CardContent, CardHeader, CardTitle } from "@/components/ui";
import type { ItemDaFila } from "@/lib/acervo/curadoria";

import { publicar, reenfileirar, type ResultadoDaCuradoria } from "./acoes";

const INICIAL: ResultadoDaCuradoria = { ok: false };

const VISIBILIDADES = [
  { valor: "publico", rotulo: "Público — qualquer pessoa, sem entrar" },
  { valor: "autenticado", rotulo: "Morador — quem tem cadastro e entrou" },
  { valor: "conselho", rotulo: "Conselho e editora" },
  { valor: "restrito", rotulo: "Conselho, editora e a unidade citada" },
];

interface Props {
  item: ItemDaFila;
  posicao: number;
  total: number;
  temProximo: boolean;
  primeirasLinhas: string[];
}

export function PainelDeConferencia({
  item,
  posicao,
  total,
  temProximo,
  primeirasLinhas,
}: Props) {
  const [estadoPublicar, acaoPublicar, publicando] = useActionState(publicar, INICIAL);
  const [estadoFila, acaoFila, reenfileirando] = useActionState(reenfileirar, INICIAL);

  return (
    <div className="space-y-6">
      <p className="text-base text-tinta-suave" aria-live="polite">
        Documento {posicao} de {total} aguardando conferência.
      </p>

      <Card>
        <CardHeader>
          <CardTitle>{item.titulo}</CardTitle>
        </CardHeader>
        <CardContent className="space-y-4">
          <p className="flex flex-wrap items-center gap-3 text-base text-tinta-suave">
            <Badge>{item.tipo}</Badge>
            {item.paginas && <span>{item.paginas} páginas</span>}
            <Link href={`/acervo/${item.id}`} className="text-acao">
              Ver o documento inteiro
            </Link>
          </p>

          {item.erro_detalhe ? (
            <div className="space-y-3">
              <p className="text-base text-erro">Erro: {item.erro_detalhe}</p>
              <form action={acaoFila}>
                <input type="hidden" name="documento_id" value={item.id} />
                <Button type="submit" variante="secundaria" disabled={reenfileirando}>
                  {reenfileirando ? "Devolvendo…" : "Tentar de novo"}
                </Button>
              </form>
              {estadoFila.mensagem && (
                <p role="status" className="text-base text-tinta">
                  {estadoFila.mensagem}
                </p>
              )}
            </div>
          ) : (
            <>
              {primeirasLinhas.length > 0 && (
                <div className="rounded-md border-2 border-borda-forte p-4">
                  <p className="mb-2 text-meta text-tinta-suave">
                    Começo do texto lido — confira se bate com o documento:
                  </p>
                  <p className="whitespace-pre-wrap font-legal text-base leading-relaxed text-tinta">
                    {primeirasLinhas.join("\n")}
                  </p>
                </div>
              )}

              <form action={acaoPublicar} className="space-y-4">
                <input type="hidden" name="documento_id" value={item.id} />
                <div className="space-y-2">
                  <label
                    htmlFor="visibilidade"
                    className="block text-base font-semibold text-tinta"
                  >
                    Quem pode ver
                  </label>
                  <select
                    id="visibilidade"
                    name="visibilidade"
                    defaultValue={item.visibilidade}
                    className="alvo-toque block w-full rounded-md border-2 border-borda-forte bg-superficie px-4 text-base text-tinta"
                  >
                    {VISIBILIDADES.map((v) => (
                      <option key={v.valor} value={v.valor}>
                        {v.rotulo}
                      </option>
                    ))}
                  </select>
                </div>

                {estadoPublicar.mensagem && (
                  <p role="alert" className="text-base text-erro">
                    Erro: {estadoPublicar.mensagem}
                  </p>
                )}

                <div className="flex flex-wrap gap-3">
                  <Button type="submit" tamanho="lg" disabled={publicando}>
                    {publicando ? "Publicando…" : "Publicar"}
                  </Button>
                  {temProximo && (
                    <Button asChild variante="secundaria" tamanho="lg">
                      <Link href={`/curadoria?i=${posicao}`}>Deixar para depois</Link>
                    </Button>
                  )}
                </div>
              </form>
            </>
          )}
        </CardContent>
      </Card>

      <p className="text-base text-tinta-suave">
        Parar no meio é normal: a fila continua de onde você deixou. Nada é publicado
        sem você clicar.
      </p>
    </div>
  );
}
