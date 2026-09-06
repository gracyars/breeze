"use client";

import { useRouter } from "next/navigation";
import { useState } from "react";

import { Button, CampoTexto } from "@/components/ui";
import { clienteDoNavegador } from "@/lib/supabase/navegador";

/**
 * Segundo fator (TOTP) — enrolamento e verificação.
 *
 * Roda no navegador porque o segredo do TOTP não pode passar pelo servidor da
 * aplicação: ele é gerado pelo Auth e vai direto para o app autenticador da
 * pessoa. O servidor do Breeze nunca precisa vê-lo e por isso não o vê.
 *
 * Nada aqui concede papel. Verificar o TOTP promove a sessão para `aal2`, e é a
 * **RLS** que passa a reconhecer `editor`/`conselho` a partir do claim (ADR-0003,
 * ADR-0012). Enquanto a sessão for `aal1`, quem é do conselho enxerga o que um
 * morador enxerga — não porque a tela esconde, porque o banco não devolve.
 */

interface Props {
  aal: string | null;
  fatorVerificado: { id: string } | null;
}

export function PainelDeSeguranca({ aal, fatorVerificado }: Props) {
  const router = useRouter();
  const [qr, setQr] = useState<string | null>(null);
  const [segredo, setSegredo] = useState<string | null>(null);
  const [fatorId, setFatorId] = useState<string | null>(fatorVerificado?.id ?? null);
  const [codigo, setCodigo] = useState("");
  const [erro, setErro] = useState<string | null>(null);
  const [ocupado, setOcupado] = useState(false);

  async function enrolar() {
    setOcupado(true);
    setErro(null);
    const supabase = clienteDoNavegador();
    const { data, error } = await supabase.auth.mfa.enroll({
      factorType: "totp",
      friendlyName: `breeze-${Date.now()}`,
    });
    setOcupado(false);
    if (error || !data) {
      setErro(error?.message ?? "Não consegui iniciar o cadastro do segundo fator.");
      return;
    }
    setFatorId(data.id);
    setQr(data.totp.qr_code);
    setSegredo(data.totp.secret);
  }

  async function verificar() {
    if (!fatorId) return;
    setOcupado(true);
    setErro(null);
    const supabase = clienteDoNavegador();
    const { error } = await supabase.auth.mfa.challengeAndVerify({
      factorId: fatorId,
      code: codigo.replace(/\D/g, ""),
    });
    setOcupado(false);
    if (error) {
      setErro("Código não confere. Verifique o app e tente de novo.");
      return;
    }
    setCodigo("");
    router.refresh();
  }

  if (aal === "aal2") {
    return (
      <p className="text-lg text-tinta" role="status">
        Segundo fator verificado nesta sessão. Se você é do conselho ou é a editora,
        seus acessos estão ativos até sair.
      </p>
    );
  }

  return (
    <div className="space-y-6">
      {/*
        Erro fora do campo, e não só dentro dele: a falha de cadastro acontece
        antes de o campo existir. Sem isto, quem clicasse em "Cadastrar" e
        recebesse recusa do Auth via nada — nem QR, nem mensagem — e a tela
        ficaria parada sem dizer por quê. Foi assim que o teste de ponta a ponta
        encontrou este defeito.
      */}
      {erro && !fatorId && (
        <p role="alert" className="text-base text-erro">
          Erro: {erro}
        </p>
      )}

      {!fatorId && (
        <>
          <p className="text-base text-tinta-suave">
            O segundo fator é obrigatório para quem publica documento ou lê dado
            financeiro nominal. Você vai precisar de um app autenticador no celular.
          </p>
          <Button onClick={enrolar} disabled={ocupado} tamanho="lg">
            {ocupado ? "Gerando…" : "Cadastrar segundo fator"}
          </Button>
        </>
      )}

      {qr && segredo && (
        <div className="space-y-4">
          <p className="text-base text-tinta">
            Leia o código no app autenticador. Se não conseguir ler, digite a chave.
          </p>
          {/*
            `<img>` cru, não `next/image`: o Auth devolve o QR como data URL de
            SVG, que o otimizador de imagem recusa — e recusa lançando, o que
            derrubava a tela inteira. Não há o que otimizar num SVG embutido.
          */}
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img
            src={qr}
            alt="Código QR para cadastrar o segundo fator no app autenticador"
            width={200}
            height={200}
          />
          <p className="font-mono text-base text-tinta break-all">{segredo}</p>
          <p className="text-base text-tinta-suave">
            <strong>Antes de continuar:</strong> gere e imprima os códigos de
            recuperação (runbook §5.1). Se você é a editora e perder o celular sem
            ter o papel, ninguém no sistema consegue devolver seu acesso de escrita.
          </p>
        </div>
      )}

      {fatorId && (
        <div className="space-y-4">
          <CampoTexto
            rotulo="Código de 6 dígitos"
            ajuda="O código muda a cada 30 segundos."
            inputMode="numeric"
            autoComplete="one-time-code"
            value={codigo}
            onChange={(evento) => setCodigo(evento.target.value)}
            erro={erro ?? undefined}
          />
          <Button onClick={verificar} disabled={ocupado || codigo.length < 6} tamanho="lg">
            {ocupado ? "Verificando…" : "Verificar"}
          </Button>
        </div>
      )}
    </div>
  );
}
