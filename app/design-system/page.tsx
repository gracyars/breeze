import type { Metadata } from "next";
import {
  Badge,
  BadgeStatus,
  Button,
  CampoTexto,
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
  Destaque,
  GraficoBarras,
  GraficoOrcadoRealizado,
  RespostaSintetizada,
  SeloProveniencia,
  Table,
  TableBody,
  TableCaption,
  TableCell,
  TableFooter,
  TableHead,
  TableHeader,
  TableRow,
  TrechoFonte,
} from "@/components/ui";

/**
 * Vitrine do design system. Não é tela de produto — é a superfície contra a
 * qual os testes de contraste, escala de fonte e alvo de toque rodam
 * (tests/a11y/). Toda primitiva nova entra aqui.
 */
export const metadata: Metadata = {
  title: "Design system — Breeze",
  robots: { index: false, follow: false },
};

function Secao({
  titulo,
  children,
}: {
  titulo: string;
  children: React.ReactNode;
}) {
  return (
    <section className="flex flex-col gap-4 border-t border-borda pt-8">
      <h2 className="text-2xl font-semibold text-tinta">{titulo}</h2>
      {children}
    </section>
  );
}

export default function PaginaDesignSystem() {
  return (
    <main className="mx-auto flex w-full max-w-4xl flex-col gap-8 px-4 py-10">
      <header className="flex flex-col gap-2">
        <h1 className="text-3xl font-semibold text-tinta">
          Design system do Breeze
        </h1>
        <p className="text-base text-tinta-suave medida-leitura">
          Base institucional-sóbria. Corpo de 18px, alvo de toque de 48px,
          contraste AA no mínimo e AAA em texto financeiro.
        </p>
      </header>

      <Secao titulo="Tipografia">
        <p className="text-4xl font-semibold numero">R$ 43.218,90</p>
        <p className="text-3xl font-semibold">Título de página — 36px</p>
        <p className="text-2xl font-semibold">Título de seção — 30px</p>
        <p className="text-xl font-semibold">Título de card — 24px</p>
        <p className="text-lg">Destaque de leitura — 20px</p>
        <p className="text-base">Corpo padrão da interface — 18px</p>
        <p className="text-meta text-tinta-suave">
          Meta, rótulo e legenda — 16px, o piso absoluto do sistema
        </p>
        <p className="texto-legal" data-testid="texto-legal">
          Art. 1.348. Compete ao síndico prestar contas à assembleia,
          anualmente e quando exigidas. Este é o corpo de texto jurídico:
          serifada humanista, 20px, entrelinha 1,75 e medida de 68 caracteres.
        </p>
      </Secao>

      <Secao titulo="Botões">
        <div className="flex flex-wrap items-center gap-4">
          <Button>Ver boleto</Button>
          <Button variante="secundaria">Baixar PDF</Button>
          <Button variante="discreta">Cancelar</Button>
          <Button tamanho="lg">Buscar no acervo</Button>
          <Button disabled>Indisponível</Button>
        </div>
      </Secao>

      <Secao titulo="Campo de texto">
        <div className="flex flex-col gap-6 md:max-w-md">
          <CampoTexto
            rotulo="CPF ou e-mail"
            ajuda="Enviamos um link de acesso para o e-mail cadastrado."
            placeholder="000.000.000-00"
          />
          <CampoTexto
            rotulo="Competência"
            erro="Use o formato MM/AAAA."
            defaultValue="13/2025"
          />
        </div>
      </Secao>

      <Secao titulo="Card e selo de proveniência">
        <Card>
          <CardHeader>
            <CardTitle>Balancete de agosto de 2025</CardTitle>
            <CardDescription>
              Conferido linha a linha contra o PDF da administradora.
            </CardDescription>
          </CardHeader>
          <CardContent>
            <p className="text-base">
              Saldo final do mês:{" "}
              <span className="numero font-semibold">R$ 128.440,12</span>
            </p>
          </CardContent>
          <SeloProveniencia
            publicadoEm="12/09/2025"
            publicadoPor="Conselho fiscal"
            natureza="oficial"
            fonte={{ href: "#", rotulo: "Ver documento original" }}
          />
        </Card>
      </Secao>

      <Secao titulo="Badges">
        <div className="flex flex-wrap items-center gap-3">
          <Badge>Ata</Badge>
          <Badge variante="acao">Convenção</Badge>
          <Badge variante="rascunho">Rascunho</Badge>
          <BadgeStatus status="positivo">dentro do orçamento</BadgeStatus>
          <BadgeStatus status="negativo">acima do orçamento</BadgeStatus>
          <BadgeStatus status="atencao">sem comprovante</BadgeStatus>
          <BadgeStatus status="neutro">em aberto</BadgeStatus>
        </div>
      </Secao>

      <Secao titulo="Tabela">
        <Table rotulo="Lançamentos de agosto de 2025">
          <TableCaption>Lançamentos de agosto de 2025</TableCaption>
          <TableHeader>
            <TableRow>
              <TableHead>Conta</TableHead>
              <TableHead>Fornecedor</TableHead>
              <TableHead numerico>Valor</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            <TableRow>
              <TableCell>Elevadores</TableCell>
              <TableCell>Atlas Manutenção</TableCell>
              <TableCell numerico>R$ 4.320,00</TableCell>
            </TableRow>
            <TableRow>
              <TableCell>Limpeza e conservação</TableCell>
              <TableCell>Alfa Serviços</TableCell>
              <TableCell numerico>R$ 11.980,55</TableCell>
            </TableRow>
            <TableRow>
              <TableCell>Água, energia e gás</TableCell>
              <TableCell>Concessionária</TableCell>
              <TableCell numerico>R$ 9.007,10</TableCell>
            </TableRow>
          </TableBody>
          <TableFooter>
            <TableRow>
              <TableCell>Total</TableCell>
              <TableCell />
              <TableCell numerico>R$ 25.307,65</TableCell>
            </TableRow>
          </TableFooter>
        </Table>
      </Secao>

      <Secao titulo="Citação: trecho-fonte e síntese">
        <RespostaSintetizada
          fontes={
            <TrechoFonte
              tipo="Regimento interno"
              data="Aprovado em 14/03/2019"
              titulo="Regimento interno — Capítulo IV, Animais"
              pagina={14}
              href="#"
            >
              É permitida a permanência de{" "}
              <Destaque>animais domésticos</Destaque> nas unidades autônomas,
              desde que não comprometam a segurança, a higiene e o sossego dos
              demais condôminos.
            </TrechoFonte>
          }
        >
          Sim, é permitido ter cachorro, desde que o animal não comprometa
          segurança, higiene e sossego.
        </RespostaSintetizada>
      </Secao>

      <Secao titulo="Gráfico: para onde foi o dinheiro">
        <GraficoBarras
          titulo="Despesas de agosto de 2025"
          itens={[
            {
              rotulo: "Pessoal e encargos",
              valor: 28400,
              rotuloValor: "R$ 28.400,00",
              rotuloPercentual: "41%",
              href: "#",
            },
            {
              rotulo: "Limpeza e conservação",
              valor: 11980,
              rotuloValor: "R$ 11.980,55",
              rotuloPercentual: "17%",
              href: "#",
            },
            {
              rotulo: "Água, energia e gás",
              valor: 9007,
              rotuloValor: "R$ 9.007,10",
              rotuloPercentual: "13%",
              href: "#",
            },
            {
              rotulo: "Elevadores",
              valor: 4320,
              rotuloValor: "R$ 4.320,00",
              rotuloPercentual: "6%",
              href: "#",
            },
          ]}
        />
      </Secao>

      <Secao titulo="Gráfico: orçado × realizado">
        <GraficoOrcadoRealizado
          titulo="Agosto de 2025"
          itens={[
            {
              rotulo: "Elevadores",
              orcado: 4000,
              realizado: 4320,
              rotuloOrcado: "R$ 4.000,00",
              rotuloRealizado: "R$ 4.320,00",
              situacao: "acima do orçamento",
              status: "negativo",
            },
            {
              rotulo: "Limpeza e conservação",
              orcado: 12500,
              realizado: 11980,
              rotuloOrcado: "R$ 12.500,00",
              rotuloRealizado: "R$ 11.980,55",
              situacao: "dentro do orçamento",
              status: "positivo",
            },
          ]}
        />
      </Secao>
    </main>
  );
}
