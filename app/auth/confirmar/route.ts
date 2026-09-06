import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";

import { clienteDoServidor } from "@/lib/supabase/servidor";

/**
 * Fim do magic link: troca o código pela sessão e manda a pessoa para dentro.
 *
 * O link do e-mail chega aqui com `code` (PKCE). A troca só funciona no mesmo
 * navegador que pediu o link, porque o verificador ficou num cookie httpOnly —
 * é o que impede que um link interceptado no meio do caminho vire sessão em
 * outra máquina.
 *
 * Erro aqui **não** diz o que aconteceu (link expirado, já usado, de outra
 * origem): a tela de entrada é a mesma para todos os casos, pelo mesmo motivo
 * que a de login é (ADR-0003).
 */
export async function GET(request: NextRequest) {
  const url = new URL(request.url);
  const codigo = url.searchParams.get("code");
  const proximo = destinoSeguro(url.searchParams.get("proximo"));

  if (!codigo) {
    return NextResponse.redirect(new URL("/entrar?falhou=1", url.origin));
  }

  const supabase = await clienteDoServidor();
  const { error } = await supabase.auth.exchangeCodeForSession(codigo);

  if (error) {
    return NextResponse.redirect(new URL("/entrar?falhou=1", url.origin));
  }

  return NextResponse.redirect(new URL(proximo, url.origin));
}

/**
 * Só caminho interno. `proximo=https://outro.site` seria redirecionamento aberto
 * — e um redirecionamento aberto logo depois do login é o veículo clássico de
 * phishing que empresta a credibilidade do domínio de quem confia.
 */
function destinoSeguro(bruto: string | null): string {
  if (!bruto) return "/";
  if (!bruto.startsWith("/") || bruto.startsWith("//")) return "/";
  return bruto;
}
