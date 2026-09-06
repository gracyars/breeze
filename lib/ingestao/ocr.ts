import { execFile } from "node:child_process";
import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { promisify } from "node:util";

import { normalizaMarcadores, normalizaUnidadeDeArea } from "@/lib/ocr/marcadores";

const executar = promisify(execFile);

/**
 * Adaptador de OCR — estágio 3 do pipeline (ADR-0025), motor local (ADR-0024).
 *
 * O motor é um **processo filho**, não uma biblioteca: o Vision é do sistema
 * operacional e falar com ele por um binário Swift mantém a fronteira explícita.
 * Trocar de motor (inclusive para a API paga, se o gatilho do ADR-0024 disparar)
 * é trocar esta implementação, não o pipeline.
 *
 * O OCR roda **fora** de qualquer transação: efeito externo dentro de transação
 * é bloat garantido, e 18 páginas segurando lock é o pior dos dois mundos.
 */

export interface PaginaOcr {
  pagina: number;
  texto: string;
  /** Média das confianças de linha, 0–1 — vai para `documento_paginas.confianca_ocr`. */
  confianca: number;
  /** Linhas que a conferência humana precisa olhar primeiro. */
  linhasSuspeitas: number;
  /** Marcadores de item corrigidos pela sequência da lista. */
  marcadoresCorrigidos: number;
}

interface SaidaBruta {
  pagina: number;
  confianca_media: number;
  texto: string;
}

/**
 * Roda o OCR local sobre páginas específicas de um PDF.
 *
 * A saída passa pelo normalizador de marcador (`lib/ocr/marcadores.ts`) antes de
 * virar texto efetivo. Isso não é polimento: em documento cuja unidade citável é
 * o item (`i.`, `ii.`, `a)`), o marcador é a parte que o reconhecedor mais erra e
 * a que mais importa — citar "item ii" onde o documento diz "item iii" é o erro
 * que destrói a credibilidade do produto.
 */
export async function ocrDePaginas(
  pdf: Uint8Array,
  paginas: readonly number[],
  dpi = 300,
): Promise<PaginaOcr[]> {
  if (paginas.length === 0) return [];

  const dir = await mkdtemp(join(tmpdir(), "breeze-ocr-"));
  const caminhoPdf = join(dir, "documento.pdf");
  try {
    await writeFile(caminhoPdf, pdf);
    await executar("swift", [
      "scripts/ocr/vision_ocr.swift",
      caminhoPdf,
      dir,
      String(dpi),
      ...paginas.map(String),
    ]);

    const resultado: PaginaOcr[] = [];
    for (const pagina of paginas) {
      const bruto = JSON.parse(
        await readFile(join(dir, `pagina-${String(pagina).padStart(3, "0")}.json`), "utf8"),
      ) as SaidaBruta;

      const linhas = normalizaMarcadores(
        bruto.texto.split("\n").map(normalizaUnidadeDeArea),
      );

      resultado.push({
        pagina: bruto.pagina,
        texto: linhas.map((l) => l.texto).join("\n"),
        confianca: Number(bruto.confianca_media.toFixed(3)),
        linhasSuspeitas: linhas.filter((l) => l.suspeita).length,
        marcadoresCorrigidos: linhas.filter((l) => l.corrigido).length,
      });
    }
    return resultado;
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
}
