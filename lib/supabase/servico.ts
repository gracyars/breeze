import "server-only";

import { createClient } from "@supabase/supabase-js";

import type { Database } from "@/lib/supabase/database.types";

/**
 * Cliente `service_role` — **bypassa RLS**. Leia isto antes de importar.
 *
 * Existe para exatamente duas classes de uso, ambas sem sessão de usuário
 * (V4 da auditoria de F0, `docs/adr/0014`):
 *
 * 1. **Lookup de login** por `cpf_hash`/e-mail: acontece antes de existir sessão,
 *    então não há como ser `authenticated`.
 * 2. **Estágios de máquina do worker** de ingestão.
 *
 * O que ele **não** é: atalho para "essa consulta deu vazio, deve ser a RLS".
 * Se um caminho servido a navegador precisar deste cliente para funcionar, o
 * defeito está na policy ou no desenho — não aqui. Toda leitura de dado do
 * condomínio para um usuário passa por `clienteDoServidor()`.
 *
 * Nota de desenho que a auditoria de F0 já travou: `service_role` **não tem
 * `INSERT` em `documentos`** e não tem `UPDATE`/`DELETE` em `pessoas` e
 * `papeis`. Este cliente não é onipotente por decisão de schema, e não é para
 * ser "consertado".
 *
 * `import "server-only"` faz o build quebrar se alguém importar isto de um
 * componente de cliente — a chave nunca chega ao navegador por acidente.
 */
export function clienteDeServico() {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const chave = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !chave) {
    throw new Error(
      "SUPABASE_SERVICE_ROLE_KEY/NEXT_PUBLIC_SUPABASE_URL ausentes — ver .env.example",
    );
  }

  return createClient<Database>(url, chave, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
}
