import { createServerClient } from "@supabase/ssr";
import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";

/**
 * Renovação de sessão a cada requisição.
 *
 * No Next 16 isto se chama Proxy (era Middleware). A única coisa que ele faz
 * aqui é chamar `getUser()` para renovar o token quando está perto de expirar e
 * regravar os cookies — Server Component não consegue gravar cookie, então sem
 * este arquivo a sessão morre sozinha no meio do uso.
 *
 * **O que ele deliberadamente não faz: autorizar.** A documentação do próprio
 * Next avisa que Proxy serve para checagem otimista, não para ser a solução de
 * autorização; no Breeze a razão é mais dura — a fronteira de autorização é uma
 * só, a RLS (ADR-0012, ADR-0023). Um `if` aqui que decidisse quem lê o quê
 * criaria uma segunda fronteira, que é exatamente o padrão que custou três
 * rodadas de auditoria em F0. Aqui só existe redirecionamento de rota privada
 * para o login: quem burlar o redirecionamento continua sem enxergar linha
 * nenhuma, porque quem nega é o banco.
 */

/** Rotas que não exigem sessão. O resto exige. */
const PUBLICAS = ["/entrar", "/auth", "/publico", "/design-system"];

export async function proxy(request: NextRequest) {
  let resposta = NextResponse.next({ request });

  const supabase = createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        getAll() {
          return request.cookies.getAll();
        },
        setAll(cookiesParaGravar) {
          for (const { name, value } of cookiesParaGravar) {
            request.cookies.set(name, value);
          }
          resposta = NextResponse.next({ request });
          for (const { name, value, options } of cookiesParaGravar) {
            resposta.cookies.set(name, value, options);
          }
        },
      },
    },
  );

  // Não remover: é esta chamada que renova o token e regrava o cookie.
  const {
    data: { user },
  } = await supabase.auth.getUser();

  const caminho = request.nextUrl.pathname;
  const ehPublica = PUBLICAS.some(
    (rota) => caminho === rota || caminho.startsWith(`${rota}/`),
  );

  if (!user && !ehPublica) {
    const destino = request.nextUrl.clone();
    destino.pathname = "/entrar";
    destino.searchParams.set("proximo", caminho);
    return NextResponse.redirect(destino);
  }

  return resposta;
}

export const config = {
  matcher: [
    // Tudo, menos estático e imagem — inclusive as rotas públicas, que precisam
    // da renovação de sessão para o cabeçalho saber quem está logado.
    "/((?!_next/static|_next/image|favicon.ico|.*\\.(?:svg|png|jpg|jpeg|gif|webp)$).*)",
  ],
};
