import { createServerClient } from "@supabase/ssr";
import { cookies } from "next/headers";

import type { Database } from "@/lib/supabase/database.types";

/**
 * Cliente Supabase de servidor, com a sessão do cookie.
 *
 * Regra que não pode ser afrouxada: **toda leitura de dado do condomínio passa
 * por aqui, como `authenticated`.** A `service_role` bypassa RLS e por isso não
 * entra em nenhum caminho servido a navegador — ela existe só para os estágios
 * de máquina do worker (`lib/supabase/servico.ts`), nunca para responder a uma
 * requisição de usuário.
 */
export async function clienteDoServidor() {
  const cookieStore = await cookies();

  return createServerClient<Database>(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        getAll() {
          return cookieStore.getAll();
        },
        setAll(cookiesParaGravar) {
          try {
            for (const { name, value, options } of cookiesParaGravar) {
              cookieStore.set(name, value, options);
            }
          } catch {
            // Server Component não pode gravar cookie. Quem renova a sessão é o
            // `proxy.ts`; aqui o silêncio é correto, não é engolir erro.
          }
        },
      },
    },
  );
}

export interface Sessao {
  usuarioId: string;
  email: string | null;
  /** `aal1` = só o primeiro fator; `aal2` = segundo fator verificado nesta sessão. */
  aal: string | null;
}

/**
 * Quem está pedindo — ou `null`.
 *
 * Usa `getUser()`, que valida o token no servidor de Auth, e **não**
 * `getSession()`, que só lê o cookie: cookie é dado que o cliente controla.
 *
 * O `aal` vem do próprio access token porque é exatamente o claim que a RLS
 * consulta (ADR-0003, ADR-0012). Ele é devolvido para a **UI** poder pedir o
 * segundo fator na hora certa — jamais para a aplicação decidir autorização por
 * conta própria. A fronteira de autorização é uma só, e é a RLS: se um `if` de
 * TypeScript for a única coisa entre um morador e a lista de inadimplentes, o
 * desenho já está errado.
 */
export async function sessaoAtual(): Promise<Sessao | null> {
  const supabase = await clienteDoServidor();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return null;

  const { data } = await supabase.auth.getSession();
  const token = data.session?.access_token;

  return {
    usuarioId: user.id,
    email: user.email ?? null,
    aal: token ? (lerClaim(token, "aal") as string | null) : null,
  };
}

/**
 * Lê um claim do access token sem validar assinatura.
 *
 * Seguro **porque** o token já foi validado por `getUser()` contra o servidor de
 * Auth logo acima, e porque o valor lido aqui só alimenta decisão de tela. Usar
 * isto para autorizar seria confiar em base64 do cliente.
 */
function lerClaim(token: string, claim: string): unknown {
  try {
    const [, carga] = token.split(".");
    return JSON.parse(Buffer.from(carga, "base64url").toString("utf8"))[claim];
  } catch {
    return null;
  }
}
