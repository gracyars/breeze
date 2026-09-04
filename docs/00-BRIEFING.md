# Breeze — Briefing do Projeto

## 1. O que é

Webapp de consulta e fiscalização para um condomínio residencial. Duas funções, uma tese:
tudo que hoje está preso em PDF vira informação consultável, e todo número financeiro
declarado pela administradora fica a um toque do documento que o comprova.

**Tese central:** o produto não é um ERP de condomínio. É uma **camada de auditoria e
transparência sobre a administradora terceirizada**. A administradora continua sendo o
sistema de registro (emite boleto, roda folha, fecha o balancete). O Breeze é onde o
conselho fiscal e os moradores verificam se aquilo faz sentido.

Essa distinção governa todo o escopo. Se uma funcionalidade existe para *substituir* a
administradora, está fora. Se existe para *fiscalizar* a administradora ou para *tornar
legível* o que ela produz, está dentro.

## 2. Contexto e parâmetros

| Parâmetro | Valor |
|---|---|
| Porte | Até ~50 unidades |
| Acervo estimado | Centenas de PDFs, parte relevante escaneada |
| Fonte do dado financeiro | Balancete mensal em PDF enviado pela administradora |
| Modelo de acesso | Camada pública (normativos) + área autenticada (acervo e finanças) |
| Execução | Agentes constroem; o dono do projeto revisa |
| Manutenção | Um mantenedor, não especialista em infraestrutura |
| Orçamento-alvo | ~R$300/mês recorrente |

## 3. Personas

- **Morador (proprietário ou inquilino)** — quer resposta a uma pergunta concreta:
  "posso ter cachorro?", "quanto gastamos com elevador esse ano?", "quando é a assembleia?".
  Não vai aprender a navegar uma estrutura de pastas. Faixa etária ampla, inclui pessoas com
  baixa familiaridade digital. Uso majoritariamente em celular.
- **Conselho fiscal** — usuário mais valioso do produto. Precisa cruzar balancete com
  comprovante, comparar orçado e realizado, registrar questionamento formal e emitir parecer.
  Hoje faz isso abrindo doze PDFs lado a lado.
- **Síndico / subsíndico** — publica documento, responde questionamento, presta contas.
  É simultaneamente operador e fiscalizado — o produto precisa funcionar mesmo quando ele
  não quer que funcione.
- **Administradora** — origem do dado. Pode ou não ter acesso; no MVP, não tem.

## 4. Dores que o produto mata

1. Informação existe, mas ninguém acha. A resposta está no regimento, mas está na página 14
   de um PDF que ninguém abre.
2. Balancete não é auditável na prática. Número sem nota fiscal ao lado é afirmação, não prova.
3. Gasto fora do orçado passa sem ninguém notar até a assembleia anual — quando já não há o que fazer.
4. Fundo de reserva usado para custeio corrente, sem ata que autorize.
5. Contrato renovado sem cotação comparativa registrada.
6. Não há trilha: quem alterou o quê, quando, e com qual justificativa.
7. Ata publicada com atraso, ou que não reflete o que foi deliberado.

## 5. Escopo

### Dentro (MVP)
- Acervo documental indexado, com busca híbrida em português e citação de página exata.
- Leitor de convenção e regimento com índice, âncora e permalink por artigo, e resumo em
  linguagem simples claramente rotulado como auxiliar.
- Importação assistida do balancete: extração da tabela, conferência humana lado a lado com o
  PDF, e travas de consistência contábil antes de publicar.
- Painel financeiro para leigos: para onde foi o dinheiro, orçado vs realizado, série histórica.
- Motor de alertas de fiscalização (seção 4 do SPEC).
- Questionamento do conselho preso ao lançamento, com status e resposta.
- Trilha de auditoria imutável com encadeamento de hash.

### Fora (explicitamente)
Emissão de boleto, PIX, CNAB, folha de pagamento, cobrança judicial, reserva de áreas comuns,
chamados/ocorrências, assembleia digital com votação, app nativo, multi-condomínio.
Reavaliar só depois que o núcleo estiver em uso real.

## 6. Como saberemos que deu certo

- Um morador encontra a resposta a uma pergunta de regimento em menos de 30 segundos, sozinho.
- O conselho fiscal emite o parecer mensal dentro do produto, sem abrir PDF fora dele.
- Todo lançamento publicado tem documento-fonte vinculado. Sem exceção.
- Um estouro de orçamento é notado no mês em que acontece, não na AGO.

## 7. Decisões pendentes do dono do projeto

1. **Publicação aberta do acervo.** Atas e balancetes contêm nome, unidade e às vezes CPF.
   Padrão adotado: público apenas convenção e regimento (normativos, impessoais); acervo e
   finanças atrás de login leve por convite. Alternativa, se houver insistência na abertura
   total: etapa obrigatória de redação/anonimização antes de publicar, com custo de operação
   recorrente. **Precisa de decisão antes da primeira publicação.**
2. Quem, além do dono do projeto, terá papel de administrador no dia 1.
3. Se o parecer do conselho emitido no produto terá valor formal perante a assembleia
   (muda o rigor exigido em assinatura e versionamento).
4. Profundidade do histórico a digitalizar: só o exercício corrente, ou o acervo completo.
