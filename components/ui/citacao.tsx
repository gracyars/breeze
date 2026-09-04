import * as React from "react";
import { cn } from "@/lib/cn";
import { Badge } from "./badge";

/**
 * Par de citação (SPEC §6.2 e §4).
 *
 * A regra que governa estes dois componentes: **o trecho original é o resultado
 * primário; a síntese é secundária**. Em condomínio, confiança vem de onde está
 * escrito. Por isso `RespostaSintetizada` exige a prop `fontes` — é
 * impossível, por tipo, renderizar síntese sem citação.
 */

/** Termo buscado dentro do trecho: negrito + realce, nunca só cor. */
export function Destaque({
  className,
  ...props
}: React.HTMLAttributes<HTMLElement>) {
  return (
    <mark
      data-slot="destaque"
      className={cn(
        "bg-acao-suave font-semibold text-tinta [&::selection]:bg-acao-suave",
        className,
      )}
      {...props}
    />
  );
}

export type TrechoFonteProps = {
  /** Tipo do documento: "Ata", "Convenção", "Balancete". */
  tipo: string;
  /** Data já formatada pelo chamador (formatação é domínio, não design system). */
  data: string;
  /** Título do documento. */
  titulo: string;
  /** Página exata de onde o trecho saiu. Sem página não existe citação. */
  pagina: number;
  /** Destino do "Abrir na página X". */
  href: string;
  /** O trecho literal. Use <Destaque> no termo buscado. */
  children: React.ReactNode;
  className?: string;
};

export function TrechoFonte({
  tipo,
  data,
  titulo,
  pagina,
  href,
  children,
  className,
}: TrechoFonteProps) {
  return (
    <article
      data-slot="trecho-fonte"
      className={cn(
        "flex flex-col gap-3 rounded-lg border border-borda bg-superficie p-5 shadow-sm",
        className,
      )}
    >
      <header className="flex flex-wrap items-center gap-2">
        <Badge variante="neutro">{tipo}</Badge>
        <span className="text-meta text-tinta-suave">{data}</span>
      </header>

      <h3 className="text-lg font-semibold text-tinta">{titulo}</h3>

      <blockquote className="border-l-4 border-borda-forte pl-4 font-serif text-lg leading-relaxed text-tinta">
        {children}
      </blockquote>

      <a
        href={href}
        className="inline-flex alvo-toque w-fit items-center rounded-md px-3 text-base font-semibold text-acao hover:bg-acao-suave"
      >
        Abrir na página {pagina}
      </a>
    </article>
  );
}

/* -------------------------------------------------------------------------- */

export type RespostaSintetizadaProps = {
  /** A síntese. Sempre visualmente secundária ao trecho. */
  children: React.ReactNode;
  /** Um ou mais <TrechoFonte>. Obrigatório: sem fonte, não há resposta. */
  fontes: React.ReactNode;
  className?: string;
};

export function RespostaSintetizada({
  children,
  fontes,
  className,
}: RespostaSintetizadaProps) {
  return (
    <section
      data-slot="resposta-sintetizada"
      aria-label="Resumo automático com as fontes"
      className={cn("flex flex-col gap-4", className)}
    >
      <div className="flex flex-col gap-3 rounded-lg border border-borda bg-superficie-muda p-5">
        <div className="flex flex-wrap items-center gap-2">
          <Badge variante="neutro">Resumo automático</Badge>
          <span className="text-meta text-tinta-suave">
            Não substitui o texto oficial. Não é interpretação jurídica.
          </span>
        </div>
        <div className="text-base text-tinta medida-leitura">{children}</div>
      </div>

      <div className="flex flex-col gap-3">
        <h2 className="text-base font-semibold uppercase tracking-wide text-tinta-suave">
          De onde veio
        </h2>
        {fontes}
      </div>
    </section>
  );
}

/* -------------------------------------------------------------------------- */

/**
 * Selo de proveniência (§6.5): nenhum número aparece sem proveniência
 * rastreável. Todo dado publicado carrega data, autor, natureza e link à fonte.
 */
export type SeloProvenienciaProps = {
  publicadoEm: string;
  publicadoPor: string;
  natureza: "oficial" | "auxiliar";
  fonte?: { href: string; rotulo: string };
  className?: string;
};

export function SeloProveniencia({
  publicadoEm,
  publicadoPor,
  natureza,
  fonte,
  className,
}: SeloProvenienciaProps) {
  return (
    <footer
      data-slot="selo-proveniencia"
      className={cn(
        "flex flex-wrap items-center gap-x-3 gap-y-2 border-t border-borda pt-3 text-meta text-tinta-suave",
        className,
      )}
    >
      <Badge variante={natureza === "oficial" ? "acao" : "neutro"}>
        {natureza === "oficial" ? "Documento oficial" : "Resumo auxiliar"}
      </Badge>
      <span>
        Publicado em {publicadoEm} por {publicadoPor}
      </span>
      {fonte ? (
        <a
          href={fonte.href}
          className="inline-flex alvo-toque items-center rounded-md px-2 font-semibold text-acao hover:bg-acao-suave"
        >
          {fonte.rotulo}
        </a>
      ) : null}
    </footer>
  );
}
