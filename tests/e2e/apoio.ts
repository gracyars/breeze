import { execFile } from "node:child_process";
import { randomUUID } from "node:crypto";
import { readFile, readFileSync } from "node:fs";
import { promisify } from "node:util";

import { codigoTotp } from "./totp";

/**
 * Apoio dos testes de ponta a ponta: sessão de editora com segundo fator, acesso
 * ao banco e envio de arquivo para o Storage.
 *
 * Tudo aqui fala com o stack local **do jeito que a aplicação fala** — Auth pelo
 * GoTrue, dados pelo PostgREST com o JWT da pessoa. O único atalho é o `psql`
 * como superusuário, e só para montar e desmontar fixture: nenhuma verificação
 * do teste passa por ele.
 */

const executar = promisify(execFile);

export const URL_SUPABASE = "http://127.0.0.1:54321";

export function env(chave: string): string {
  const arquivo = readFileSync(new URL("../../.env.local", import.meta.url), "utf8");
  const linha = arquivo.split("\n").find((l) => l.startsWith(`${chave}=`));
  if (!linha) throw new Error(`${chave} ausente em .env.local`);
  return linha.slice(chave.length + 1).trim();
}

export const CHAVE_SERVICO = env("SUPABASE_SERVICE_ROLE_KEY");
export const CHAVE_ANON = env("NEXT_PUBLIC_SUPABASE_ANON_KEY");

export const REGIMENTO =
  "Documentos do Condomínio/RI - Regulamento Interno - Breeze Bosque da Saúde.pdf";

/**
 * Outro documento nativo do acervo, para teste que não pode esbarrar na
 * deduplicação: dois testes do mesmo arquivo subindo o Regimento fazem o segundo
 * ser recusado como duplicata — corretamente — e medir um documento vazio.
 */
export const PROCEDIMENTOS_REFORMA =
  "Documentos do Condomínio/PROCEDIMENTOS PARA EXECUÇÃO DE REFORMAS BREEZE + ANEXOS.pdf";

/** Escaneada, 0 caractere nativo — é o documento que exercita o caminho de OCR. */
export const CONVENCAO =
  "Documentos do Condomínio/Breeze-Bosque-da-Saude-Convencao-de-Condominio-registrada.pdf";

export async function sql(comando: string): Promise<string> {
  const { stdout } = await executar("docker", [
    "exec",
    "supabase_db_breeze",
    "psql",
    "-U",
    "postgres",
    "-d",
    "postgres",
    // `-q`: sem ele o psql imprime "INSERT 0 1" junto com o valor de `returning`
    // e o id volta com lixo colado.
    "-qtAc",
    comando,
  ]);
  return stdout.trim();
}

export async function auth(
  caminho: string,
  corpo: unknown,
  token?: string,
): Promise<Record<string, unknown>> {
  const resposta = await fetch(`${URL_SUPABASE}/auth/v1${caminho}`, {
    method: "POST",
    headers: {
      apikey: token ? CHAVE_ANON : CHAVE_SERVICO,
      authorization: `Bearer ${token ?? CHAVE_SERVICO}`,
      "content-type": "application/json",
    },
    ...(corpo ? { body: JSON.stringify(corpo) } : {}),
  });
  return (await resposta.json()) as Record<string, unknown>;
}

export interface Editora {
  email: string;
  pessoaId: string;
  /** Segredo do TOTP — o teste faz o papel do app autenticador da pessoa. */
  segredoTotp: string;
  /** Sessão só com o primeiro fator — na prática, uma moradora. */
  aal1: string;
  /** Sessão com o segundo fator verificado — só ela publica. */
  aal2: string;
}

/**
 * Cria uma editora com segundo fator verificado.
 *
 * O `prefixo` marca as linhas desta execução: os testes rodam em paralelo, cada
 * worker com sua cópia do módulo, e limpeza sem escopo apaga a fixture de quem
 * ainda está usando.
 */
export async function editoraComSegundoFator(prefixo: string): Promise<Editora> {
  const email = `${prefixo}-${randomUUID()}@breeze.local`;
  const usuario = (await auth("/admin/users", { email, email_confirm: true })) as {
    id: string;
  };

  const pessoaId = await sql(
    `insert into public.pessoas (auth_user_id, nome, email)
     values ('${usuario.id}', 'Editora de Teste', '${email}') returning id`,
  );
  await sql(
    `insert into public.papeis (pessoa_id, papel, mandato_inicio)
     values ('${pessoaId}', 'editor', current_date)`,
  );

  const link = (await auth("/admin/generate_link", { type: "magiclink", email })) as {
    email_otp: string;
  };
  // `POST /verify` espera o código do e-mail junto com o e-mail; o `hashed_token`
  // é do link clicável (`GET`). Trocar os dois falha com uma mensagem que não
  // explica isso.
  const sessao = (await auth("/verify", {
    type: "magiclink",
    email,
    token: link.email_otp,
  })) as { access_token?: string };
  if (!sessao.access_token) throw new Error("verify do magic link não devolveu sessão");

  const fator = (await auth(
    "/factors",
    { factor_type: "totp", friendly_name: `teste-${Date.now()}-${randomUUID().slice(0, 6)}` },
    sessao.access_token,
  )) as { id: string; totp?: { secret: string } };
  if (!fator.totp) throw new Error(`enrolamento recusado: ${JSON.stringify(fator)}`);

  const desafio = (await auth(
    `/factors/${fator.id}/challenge`,
    null,
    sessao.access_token,
  )) as { id: string };

  const promovido = (await auth(
    `/factors/${fator.id}/verify`,
    { challenge_id: desafio.id, code: codigoTotp(fator.totp.secret) },
    sessao.access_token,
  )) as { access_token?: string };
  if (!promovido.access_token) {
    throw new Error(`promoção para aal2 recusada: ${JSON.stringify(promovido)}`);
  }

  return {
    email,
    pessoaId,
    segredoTotp: fator.totp.secret,
    aal1: sessao.access_token,
    aal2: promovido.access_token,
  };
}

export async function enviaParaStorage(
  caminhoLocal: string,
  storagePath: string,
): Promise<void> {
  const conteudo = await promisify(readFile)(caminhoLocal);
  const resposta = await fetch(
    `${URL_SUPABASE}/storage/v1/object/documentos/${storagePath}`,
    {
      method: "POST",
      headers: {
        apikey: CHAVE_SERVICO,
        authorization: `Bearer ${CHAVE_SERVICO}`,
        "content-type": "application/pdf",
      },
      body: new Uint8Array(conteudo),
    },
  );
  if (!resposta.ok) {
    throw new Error(`storage recusou o arquivo: ${resposta.status}`);
  }
}

/**
 * Cria o documento com id conhecido, sem depender de `returning`.
 *
 * É como a aplicação faz: quem vai enviar o arquivo já precisa do id. (Até a
 * migração `20260906100500`, `insert ... returning` nesta tabela era recusado
 * para todo mundo — a policy de leitura reconsultava a tabela e não via a linha
 * nascendo.)
 */
export async function criaDocumento(
  token: string,
  campos: Record<string, unknown>,
): Promise<Response> {
  return fetch(`${URL_SUPABASE}/rest/v1/documentos`, {
    method: "POST",
    headers: {
      apikey: CHAVE_ANON,
      authorization: `Bearer ${token}`,
      "content-type": "application/json",
    },
    body: JSON.stringify(campos),
  });
}

/** Roda o worker até esvaziar a fila. */
export async function drenaFila(): Promise<void> {
  await executar("pnpm", ["worker:uma-vez"], { cwd: process.cwd() });
}

export async function buscaComo(
  token: string | null,
  consulta: string,
  limite = 10,
): Promise<{ titulo: string; secao: string | null; trecho: string }[]> {
  const resposta = await fetch(`${URL_SUPABASE}/rest/v1/rpc/buscar_lexica`, {
    method: "POST",
    headers: {
      apikey: CHAVE_ANON,
      ...(token ? { authorization: `Bearer ${token}` } : {}),
      "content-type": "application/json",
    },
    body: JSON.stringify({ p_consulta: consulta, p_limite: limite }),
  });
  if (!resposta.ok) {
    throw new Error(`busca falhou: ${resposta.status} ${await resposta.text()}`);
  }
  return (await resposta.json()) as {
    titulo: string;
    secao: string | null;
    trecho: string;
  }[];
}

const URL_MAILPIT = "http://127.0.0.1:54324";

/**
 * O link do magic link, lido da caixa de entrada local.
 *
 * Pelo Mailpit, como um morador leria no e-mail dele — o teste não pula a etapa
 * do e-mail, porque é justamente ela que o produto usa no lugar de senha.
 */
export async function linkDoUltimoEmail(destinatario: string): Promise<string | null> {
  for (let tentativa = 0; tentativa < 20; tentativa += 1) {
    const lista = (await (
      await fetch(`${URL_MAILPIT}/api/v1/messages`)
    ).json()) as { messages: { ID: string; To: { Address: string }[] }[] };

    const mensagem = lista.messages.find((m) =>
      m.To.some((t) => t.Address === destinatario),
    );
    if (mensagem) {
      const corpo = (await (
        await fetch(`${URL_MAILPIT}/api/v1/message/${mensagem.ID}`)
      ).json()) as { HTML?: string; Text?: string };
      const texto = `${corpo.HTML ?? ""}${corpo.Text ?? ""}`;
      const link = texto
        .match(/https?:\/\/[^"'\s<>]+/g)
        ?.find((u) => u.includes("verify"));
      return link ? link.replace(/&amp;/g, "&") : null;
    }
    await new Promise((resolva) => setTimeout(resolva, 250));
  }
  return null;
}
