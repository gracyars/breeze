import * as React from "react";
import { cn } from "@/lib/cn";
import { BadgeStatus } from "./badge";

/**
 * Gráficos permitidos no Breeze. Regras completas em docs/design/graficos.md.
 *
 * PROIBIDO no produto: pizza/rosca, séries sobrepostas, e qualquer gráfico sem
 * rótulo direto no elemento (legenda ou tooltip não contam — o público não
 * infere valor por cor).
 *
 * Estes componentes tornam a regra impossível de violar: `rotuloValor` é
 * obrigatório por item, a ordenação decrescente é feita aqui dentro, e a barra
 * é `aria-hidden` porque o valor já está em texto ao lado dela.
 */

export type ItemBarra = {
  /** Nome da categoria. Ex.: "Elevadores". */
  rotulo: string;
  /** Valor bruto, só para calcular o comprimento da barra. */
  valor: number;
  /** Valor já formatado pelo chamador. Ex.: "R$ 4.320,00". Obrigatório. */
  rotuloValor: string;
  /** Participação já formatada. Ex.: "18%". */
  rotuloPercentual?: string;
  /** Torna a linha clicável até o lançamento (§6.4). */
  href?: string;
};

function largura(valor: number, maximo: number): string {
  if (maximo <= 0) return "0%";
  return `${Math.max(1, Math.round((valor / maximo) * 100))}%`;
}

/**
 * Barras horizontais ordenadas do maior para o menor, com valor rotulado
 * ao lado do nome da categoria (SPEC §6.4, camada 2).
 */
export function GraficoBarras({
  titulo,
  itens,
  className,
}: {
  titulo: string;
  itens: ItemBarra[];
  className?: string;
}) {
  const ordenados = [...itens].sort((a, b) => b.valor - a.valor);
  const maximo = ordenados[0]?.valor ?? 0;

  return (
    <section
      data-slot="grafico-barras"
      className={cn("flex flex-col gap-4", className)}
    >
      <h3 className="text-xl font-semibold text-tinta">{titulo}</h3>
      <ul className="flex flex-col gap-4">
        {ordenados.map((item) => (
          <li key={item.rotulo} className="flex flex-col gap-1.5">
            <div className="flex flex-wrap items-baseline justify-between gap-x-3 gap-y-1">
              {item.href ? (
                <a
                  href={item.href}
                  className="inline-flex alvo-toque items-center rounded-md text-base font-semibold text-acao"
                >
                  {item.rotulo}
                </a>
              ) : (
                <span className="text-base font-semibold text-tinta">
                  {item.rotulo}
                </span>
              )}
              <span className="numero text-base font-semibold text-tinta">
                {item.rotuloValor}
                {item.rotuloPercentual ? (
                  <span className="font-normal text-tinta-suave">
                    {" · "}
                    {item.rotuloPercentual}
                  </span>
                ) : null}
              </span>
            </div>
            <div
              aria-hidden="true"
              className="h-4 w-full overflow-hidden rounded-sm border border-grafico-contorno bg-superficie-alt"
            >
              <div
                className="h-full bg-grafico-realizado"
                style={{ width: largura(item.valor, maximo) }}
              />
            </div>
          </li>
        ))}
      </ul>
    </section>
  );
}

/* -------------------------------------------------------------------------- */

export type ItemOrcado = {
  rotulo: string;
  orcado: number;
  realizado: number;
  /** Valores já formatados. Obrigatórios: nada de tooltip. */
  rotuloOrcado: string;
  rotuloRealizado: string;
  /** Texto do veredito. Ex.: "dentro do orçamento" / "acima do orçamento". */
  situacao: string;
  status: "positivo" | "negativo" | "atencao";
  href?: string;
};

/**
 * Barras pareadas orçado × realizado (SPEC §6.4, camada 3).
 * Duas barras empilhadas por categoria — nunca sobrepostas, nunca empilhadas
 * numa barra só. Cada barra tem prefixo textual e valor próprio.
 */
export function GraficoOrcadoRealizado({
  titulo,
  itens,
  className,
}: {
  titulo: string;
  itens: ItemOrcado[];
  className?: string;
}) {
  const maximo = itens.reduce(
    (m, i) => Math.max(m, i.orcado, i.realizado),
    0,
  );

  return (
    <section
      data-slot="grafico-orcado-realizado"
      className={cn("flex flex-col gap-6", className)}
    >
      <h3 className="text-xl font-semibold text-tinta">{titulo}</h3>
      <ul className="flex flex-col gap-6">
        {itens.map((item) => (
          <li key={item.rotulo} className="flex flex-col gap-2">
            <div className="flex flex-wrap items-center justify-between gap-2">
              {item.href ? (
                <a
                  href={item.href}
                  className="inline-flex alvo-toque items-center rounded-md text-base font-semibold text-acao"
                >
                  {item.rotulo}
                </a>
              ) : (
                <span className="text-base font-semibold text-tinta">
                  {item.rotulo}
                </span>
              )}
              <BadgeStatus status={item.status}>{item.situacao}</BadgeStatus>
            </div>

            {(
              [
                {
                  nome: "Orçado",
                  valor: item.orcado,
                  texto: item.rotuloOrcado,
                  cor: "bg-grafico-orcado",
                },
                {
                  nome: "Realizado",
                  valor: item.realizado,
                  texto: item.rotuloRealizado,
                  cor: "bg-grafico-realizado",
                },
              ] as const
            ).map((serie) => (
              <div key={serie.nome} className="flex flex-col gap-1">
                <div className="flex flex-wrap items-baseline justify-between gap-x-3">
                  <span className="text-meta text-tinta-suave">{serie.nome}</span>
                  <span className="numero text-base font-semibold text-tinta">
                    {serie.texto}
                  </span>
                </div>
                <div
                  aria-hidden="true"
                  className="h-4 w-full overflow-hidden rounded-sm border border-grafico-contorno bg-superficie-alt"
                >
                  <div
                    className={cn("h-full", serie.cor)}
                    style={{ width: largura(serie.valor, maximo) }}
                  />
                </div>
              </div>
            ))}
          </li>
        ))}
      </ul>
    </section>
  );
}
