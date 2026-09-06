import Link from "next/link";

import { sessaoAtual } from "@/lib/supabase/servidor";

/**
 * Cabeçalho do produto.
 *
 * Mostra o que a pessoa pode fazer — não o que ela pode ver. Esconder link não é
 * autorização: quem digitar a rota continua batendo na RLS, que é quem decide.
 * O aviso de segundo fator aparece porque é acionável, não como advertência.
 */
export async function Cabecalho() {
  const sessao = await sessaoAtual();

  return (
    <header className="border-b-2 border-borda-forte bg-superficie">
      <nav
        aria-label="Principal"
        className="mx-auto flex w-full max-w-4xl flex-wrap items-center gap-4 px-4 py-3"
      >
        <Link href="/" className="font-semibold text-tinta no-underline">
          Breeze
        </Link>
        <Link href="/buscar" className="text-acao">
          Buscar
        </Link>
        {sessao && (
          <>
            <Link href="/acervo" className="text-acao">
              Acervo
            </Link>
            <Link href="/curadoria" className="text-acao">
              Conferência
            </Link>
          </>
        )}
        <span className="flex-1" />
        {sessao ? (
          <>
            {sessao.aal !== "aal2" && (
              <Link href="/seguranca" className="text-base text-acao">
                Verificar segundo fator
              </Link>
            )}
            <span className="text-meta text-tinta-suave">{sessao.email}</span>
          </>
        ) : (
          <Link href="/entrar" className="text-acao">
            Entrar
          </Link>
        )}
      </nav>
    </header>
  );
}
