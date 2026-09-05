# Parecer — Visibilidade de cotação e proposta comercial

**Origem:** divergência achada pelo `arquiteto` em `docs/inventario-acervo.md` — #13 (propostas de
portaria remota) como `autenticado`, #35–37 (cotações concorrentes de segurança) como `conselho`.
Com a D13 (ADR-0019), `documentos.visibilidade` virou o piso do arquivo e classificação divergente
passa a falhar na importação. Regra pedida para o acervo inteiro, não correção caso a caso.

**Veredito: APROVADO COM CONDIÇÃO.** #35–37 em `conselho` está **certo**. #13 em `autenticado`
está **certo se for o comunicado**, não a proposta — condição C1 abaixo.

**Base legal:** guarda e tratamento — obrigação legal (LGPD art. 7º, II; CC art. 1.348, VIII).
Exibição do agregado ao morador — legítimo interesse (art. 7º, IX), fiscalização da gestão.
Restrição da íntegra — necessidade (art. 6º, III).
**Retenção:** 5 anos (Lei 4.591/64, art. 22, §1º, "g"); se a cotação fundamentou contrato,
acompanha a documentação de obras — vigência do contrato + 5 anos.

---

## 1. Não é divergência: são dois artefatos

**Classifica-se o artefato, não o assunto.** "Propostas de portaria remota" é o assunto de dois
documentos diferentes:

| | Artefato | Emissor | Destinatário original |
|---|---|---|---|
| #13, 1 página, pasta `Comunicados/` | Comunicado / quadro comparativo | Administração | **Os moradores** |
| #35–37, 8/8/27 páginas, pasta `Orçamentos Segurança/` | Propostas comerciais na íntegra | Fornecedores | A administração |

Mesmo assunto, funções distintas, visibilidades distintas. Quem classificar pelo assunto vai
reproduzir esta divergência em toda importação futura.

## 2. Regra

**R1 — Proposta comercial na íntegra → `conselho`.** Três razões, em ordem de força:

1. **Consistência de caminho de upload.** A mesma cotação, anexada a um lançamento, já é
   `conselho`/`editor` por SPEC §2 (`lancamento_anexos`). Se, entrando como `documentos`, virasse
   `autenticado`, a visibilidade do **mesmo arquivo** passaria a depender de por onde ele foi
   carregado. Isso não é política, é acidente — e é a mesma família de divergência calada que o
   projeto combate na armadilha nº1.
2. **PII de pessoa natural.** A íntegra carrega, de praxe, nome, CPF, telefone e e-mail do
   representante, assinatura, e ART/CREA do responsável técnico — dado pessoal (art. 5º, I) de
   terceiro que não é condômino. A finalidade que justifica mostrar algo ao morador (verificar que
   houve concorrência) não precisa do celular do vendedor. Necessidade, art. 6º, III.
3. **D13 faz a página mais sensível arrastar o arquivo.** Com o piso, não existe "documento
   `autenticado` com a página do CPF em `conselho`": ou o documento inteiro desce, ou o dado sai
   pelo bucket.

**O que explicitamente NÃO é razão — e registro para ninguém inventar depois:** "preço de
fornecedor é sigiloso". Preço de pessoa jurídica **não é dado pessoal** (art. 5º, I alcança só
pessoa natural), e o condomínio não prometeu sigilo a ninguém. O interesse comercial do fornecedor
é risco de negócio da dona do projeto, não fundamento de veto deste agente. Se alguém quiser
restringir por esse motivo, é decisão de produto, e precisa de outro dono.

**R2 — A prova de concorrência chega ao morador como dado estruturado, não como arquivo.**
O alerta "cotação ausente" (§5.3) não pressupõe que o condômino leia 27 páginas; pressupõe que ele
possa verificar que **houve** mais de uma proposta. O morador vê quantidade de cotações, razão
social de cada proponente PJ, valor e data — de `lancamento_anexos` e `fornecedores`. A íntegra
fica com quem tem o dever de conferir. **Não é regra nova:** é o desenho já usado para
inadimplência — agregado para o morador, íntegra para a gestão.
*Canto:* proponente pessoa física ou MEI — a razão social **é** dado pessoal. Mostrar só a
contagem e os valores, sem nome. Mesma lógica da supressão de faixa N=1 (`lgpd-condominio` §4).

**R3 — Comunicado ou quadro comparativo da administração → `autenticado`**, desde que não carregue
PII de pessoa natural nem dado bancário. A finalidade do artefato é justamente informar o morador,
e ele já foi distribuído a todos: publicá-lo no acervo não acrescenta exposição alguma. Se
carregar, desce para `conselho`.

**R4 — Cotação nunca é `publico` nem `restrito`.** Não é normativa e impessoal (afasta `publico`);
não é vinculada a uma unidade (afasta `restrito` — cotação não é de ninguém).

**R5 — Cotação entra com visibilidade uniforme; não usar override de página.** Com D13 o override
só amplia, e ampliar páginas de uma proposta `conselho` é custo de curadoria sem benefício — a
necessidade do morador já está atendida por R2 — enquanto cada override é superfície nova de erro.

## 3. Condição

- **C1.** Verificar a página única de #13 antes da importação. Se ela contiver CPF, telefone,
  e-mail de pessoa natural ou dado bancário, reclassificar para `conselho` — o título
  "PROPOSTAS DAS EMPRESAS" não garante que seja o comparativo. Não li o PDF; classifiquei pelo
  artefato inferido de tamanho e pasta.

## 4. Efeito na skill `condominio-documentos` — aplicado

Era a causa raiz: #35–37 foram classificados como "Documentação de obras", cujo padrão na skill é
`autenticado`, e a §12 só tratava a cotação como **anexo**, nunca como documento próprio. Editado:

- Nova **§12-bis "Cotações e propostas comerciais"** com R1–R5.
- §12 passa a remeter à §12-bis em vez de deixar a cotação-documento sem regra.
- Sinais de reconhecimento e linha de retenção para o tipo.
- Nota na abertura: `conselho` também protege PII de terceiro não-condômino, não só dado sensível
  individualizado de morador.

## 5. Checklist

- [x] `juridico-lgpd`: §12-bis em `condominio-documentos`
- [ ] `arquiteto`: aplicar #35–37 = `conselho` no `inventario-acervo.md` e resolver C1 para #13
- [ ] `eng-supabase`: expor contagem/proponente/valor de cotação ao `morador` (R2) — F1, junto do
      alerta §5.3; sem isso o alerta chega ao morador sem prova conferível
- [ ] `auditor-rls`: teste — `morador` lendo documento de cotação → 0 linhas em `documentos`,
      `documento_paginas` e `chunks`
