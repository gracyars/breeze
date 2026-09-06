import "server-only";

import { Pool } from "pg";

/**
 * Conexão direta com o Postgres, para o que o PostgREST **não** expõe.
 *
 * Hoje isso é só a fila: o schema `job` está deliberadamente fora de
 * `api.schemas` (ADR-0007, ADR-0025 §7) porque nenhuma tela precisa dela e o
 * payload carrega caminho de storage. Expor o schema só para conseguir chamar
 * `job.enfileirar` do navegador seria alargar a superfície da API para resolver
 * um problema de servidor — o servidor já pode falar com o banco.
 *
 * A sessão assume `service_role`, que é o mesmo teto de privilégio da aplicação
 * e é imposto pelo próprio Postgres. **Isto não substitui a RLS em lugar
 * nenhum:** o que passa por aqui é enfileiramento, e ele só acontece depois de
 * uma escrita que a RLS já autorizou (o `insert` em `documentos` como a editora).
 */
let pool: Pool | undefined;

export function bancoDireto(): Pool {
  if (!pool) {
    const url = process.env.SUPABASE_DB_URL;
    if (!url) throw new Error("SUPABASE_DB_URL ausente — ver .env.example");
    pool = new Pool({ connectionString: url, max: 3 });
    pool.on("connect", (cliente) => {
      void cliente.query("set role service_role");
    });
  }
  return pool;
}
