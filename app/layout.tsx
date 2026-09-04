import type { Metadata } from "next";
import { IBM_Plex_Sans, Source_Serif_4 } from "next/font/google";
import "./globals.css";

// UI e números: sans humanista, institucional, algarismos com `tnum` real.
// Justificativa completa em docs/design-system.md §Tipografia.
const fonteUi = IBM_Plex_Sans({
  variable: "--fonte-ui",
  subsets: ["latin", "latin-ext"],
  weight: ["400", "500", "600", "700"],
  display: "swap",
});

// Corpo de texto jurídico: serifada desenhada para leitura longa em tela.
const fonteLegal = Source_Serif_4({
  variable: "--fonte-legal",
  subsets: ["latin", "latin-ext"],
  display: "swap",
});

export const metadata: Metadata = {
  title: "Breeze",
  description:
    "Consulta e fiscalização do condomínio: documentos, contas e a fonte de cada número.",
};

export default function RootLayout({ children }: LayoutProps<"/">) {
  return (
    <html
      lang="pt-BR"
      className={`${fonteUi.variable} ${fonteLegal.variable} h-full`}
    >
      <body className="flex min-h-full flex-col">{children}</body>
    </html>
  );
}
