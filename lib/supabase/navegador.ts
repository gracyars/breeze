import { createBrowserClient } from "@supabase/ssr";

import type { Database } from "@/lib/supabase/database.types";

/**
 * Cliente Supabase do navegador — só a chave publicável, nunca a `service_role`.
 *
 * Ele existe para o que precisa acontecer no cliente e não pode passar pelo
 * servidor: o fluxo de segundo fator (enrolar, desafiar, verificar TOTP) e a
 * troca do código do magic link por sessão. Leitura de acervo é Server
 * Component; se um componente de cliente estiver buscando documento, é sinal de
 * que o corte está no lugar errado.
 *
 * A autorização não mora aqui. Este cliente fala com o Postgres como
 * `authenticated`, e é a RLS que decide o que ele enxerga (ADR-0012). Nada que
 * este arquivo faça — ou deixe de fazer — amplia acesso.
 */
export function clienteDoNavegador() {
  return createBrowserClient<Database>(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
  );
}
