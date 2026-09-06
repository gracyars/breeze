import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  // Só desenvolvimento: o `next dev` bloqueia recursos internos (HMR) pedidos de
  // uma origem diferente da que serviu a página. Como a base do Playwright e do
  // `.env.local` é `127.0.0.1` e o dev server anuncia `localhost`, a hidratação
  // ficava sem completar — a página aparecia certa e nenhum clique funcionava,
  // sem erro no console. Não afeta produção.
  allowedDevOrigins: ["127.0.0.1", "localhost"],
};

export default nextConfig;
