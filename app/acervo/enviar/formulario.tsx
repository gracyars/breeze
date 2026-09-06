"use client";

import { useRouter } from "next/navigation";
import { useActionState, useState } from "react";

import { Button, CampoTexto } from "@/components/ui";

import { confirmarEnvio, iniciarEnvio, type EnvioIniciado } from "./acoes";

const INICIAL: EnvioIniciado = { ok: false };

interface Props {
  tipos: { codigo: string; nome: string }[];
}

/**
 * Envio de documento em dois tempos.
 *
 * O arquivo vai **direto do navegador para o bucket**, por URL assinada — não
 * passa pelo servidor da aplicação. Isso não é otimização: é o que evita ter um
 * caminho de servidor que aceita arquivo grande de quem estiver logado.
 */
export function FormularioDeEnvio({ tipos }: Props) {
  const router = useRouter();
  const [estado, acao, enviando] = useActionState(iniciarEnvio, INICIAL);
  const [arquivo, setArquivo] = useState<File | null>(null);
  const [subindo, setSubindo] = useState(false);
  const [erro, setErro] = useState<string | null>(null);

  async function enviaArquivo() {
    if (!arquivo || !estado.urlDeUpload || !estado.documentoId) return;
    setSubindo(true);
    setErro(null);
    try {
      const resposta = await fetch(estado.urlDeUpload, {
        method: "PUT",
        headers: { "content-type": "application/pdf" },
        body: arquivo,
      });
      if (!resposta.ok) throw new Error(`o bucket recusou o arquivo (${resposta.status})`);

      const { ok } = await confirmarEnvio(estado.documentoId);
      if (!ok) throw new Error("não consegui pôr o documento na fila de leitura");

      router.push(`/acervo/${estado.documentoId}`);
    } catch (falha) {
      setErro(falha instanceof Error ? falha.message : "falha ao enviar o arquivo");
    } finally {
      setSubindo(false);
    }
  }

  if (estado.ok && estado.documentoId) {
    return (
      <div className="space-y-6">
        <p className="text-lg text-tinta">Documento registrado. Agora o arquivo.</p>
        <input
          type="file"
          accept="application/pdf"
          className="block w-full text-base"
          onChange={(evento) => setArquivo(evento.target.files?.[0] ?? null)}
        />
        {erro && (
          <p role="alert" className="text-base text-erro">
            Erro: {erro}
          </p>
        )}
        <Button onClick={enviaArquivo} disabled={!arquivo || subindo} tamanho="lg">
          {subindo ? "Enviando…" : "Enviar arquivo"}
        </Button>
      </div>
    );
  }

  return (
    <form action={acao} className="space-y-6">
      <CampoTexto
        rotulo="Título do documento"
        ajuda="Como o morador vai encontrar: 'Ata da AGE de 04/02/2026'."
        name="titulo"
        required
      />
      <div className="space-y-2">
        <label htmlFor="tipo" className="block text-base font-semibold text-tinta">
          Tipo
        </label>
        <select
          id="tipo"
          name="tipo"
          required
          className="alvo-toque block w-full rounded-md border-2 border-borda-forte bg-superficie px-4 text-base text-tinta"
        >
          {tipos.map((tipo) => (
            <option key={tipo.codigo} value={tipo.codigo}>
              {tipo.nome}
            </option>
          ))}
        </select>
        <p className="text-base text-tinta-suave">
          O tipo define a visibilidade padrão. Você confere antes de publicar.
        </p>
      </div>

      {estado.mensagem && (
        <p role="alert" className="text-base text-erro">
          Erro: {estado.mensagem}
        </p>
      )}

      <Button type="submit" tamanho="lg" disabled={enviando}>
        {enviando ? "Registrando…" : "Registrar documento"}
      </Button>
    </form>
  );
}
