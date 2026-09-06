# Decisões de domínio — taxonomia documental

Entradas curtas que registram uma decisão de classificação documental já pesquisada, para não
repetir a pesquisa. Não é a taxonomia em si — ver skill `condominio-documentos`. Mesmo princípio
de registro do `plano-de-contas-decisoes.md`: toda entrada lista o que **entra** e o que **sai**,
com o motivo — nunca um resumo do que "mudou".

Gatilho: `docs/inventario-acervo.md` (sondagem de 43 PDFs reais) encontrou 24/43 documentos (56%)
sem tipo formal, uma espécie de assembleia (AGI) fora do enum, um par resumo/ata com risco de
citação errada, e um lote de documentos de entrega de obra (condomínio tem ~8 meses de vida).
Fontes lidas: `docs/01-SPEC.md` §2, §2.1, §3, §7; `docs/04-DECISOES.md` D2, D3, D4, D11–D13;
`docs/schema.md` §6 e §7; skills `condominio-documentos`, `condominio-legal`,
`rag-citacao-juridica-ptbr`.

**Regra de fundo herdada, não renegociada aqui:** só convenção e regimento são públicos (D2,
Briefing §7 decisão 1). Nenhuma decisão abaixo torna um tipo novo público — onde havia um
argumento de conteúdo impessoal (Habite-se), ele é registrado como item em aberto para
`juridico-lgpd`, não decidido por conta própria. Visibilidade default de todo tipo novo é
`autenticado`, salvo quando o conteúdo típico já é conhecidamente mais sensível (dado
individualizado por unidade → `restrito`, seguindo a régua já fixada para inadimplência e
notificação).

---

## 1. "Comunicado" — confirma o 14º tipo, estreita o escopo, cria um 15º

**Pergunta:** `comunicado` vira tipo de primeira classe? Precisa de subtipos?

**Resposta: sim, já é** — `supabase/migrations/20260904120700_tipos_documento_seed.sql` já o
adicionou (`codigo='comunicado'`, autenticado, 24 meses). Essa parte não muda. O que faltava — e
esta entrada resolve — é a skill `condominio-documentos` não ter seção própria (o tipo existe no
banco e não na taxonomia de referência: a fonte ficou incompleta) e o escopo do tipo estar largo
demais para uma retenção única.

**O que entra:**

- **Seção "14. Comunicado avulso"** na skill, com metadados e sinais (abaixo), cobrindo
  esclarecimento de boleto, liberação de espaço comum, mudança de sistema de segurança, comunicado
  urgente de cota, rateio de enxoval, gerência de atendimento — a massa financeira/operacional/
  institucional do acervo.
- **Campo de categoria** (`financeiro | operacional | institucional`) como metadado do documento,
  não como tipo novo — refletido em busca por faceta, não em `tipos_documento.codigo`.
- **Tipo novo `comunicado_governanca`** (15º), separado de `comunicado` — ver razão abaixo.

**O que sai:** a ideia (levantada no brief que originou esta pesquisa) de um subtipo
"edital/convocação" dentro de `comunicado`. **Não existe.** Ver §1.1.

**Por que separar `comunicado_governanca`:** carta de apresentação de gestão e carta de renúncia
de síndico não são avisos ephemeral — são o registro de início/fim de mandato de quem o produto
existe para fiscalizar (D3: síndico terceirizado é o fiscalizado; D4: com editora única, o
registro de quem geriu quando é parte do contrapeso). Têm o mesmo valor evidencial de uma ata em
disputa sobre destituição por má gestão (**CC art. 1.349** — condominio-legal §1) e sobre o dever
de prestar contas (**CC art. 1.348, VIII**). Reter isso por 24 meses e depois permitir expurgo é
inconsistente com o resto do produto (atas e pareceres são permanentes pela mesma lógica). Manter
os dois sob o mesmo código e dar retenção diferenciada por linha não é possível hoje —
`tipos_documento.retencao_meses` é um valor por `codigo` (schema.md §6.1) — então a saída limpa é
separar o tipo, não inventar um mecanismo de retenção por subtipo que mais ninguém usa.

**Metadado que amarra ao D3:** quando o evento é sobre o síndico terceirizado (o caso real do
acervo — "Carta de Renúncia — Síndico [NOME]"), o vínculo correto é `fornecedores.id`
(`eh_sindico_terceirizado = true`), **nunca** `papeis.id` — porque D3 é explícito: síndico
terceirizado não tem papel, não tem conta, é atributo de fornecedor. Se o evento for sobre
subsíndica/conselho (pessoas com conta), o vínculo é `papeis.id`. O classificador humano decide
qual dos dois na conferência (SPEC §3, item 5); o LLM de triagem só sugere.

### 1.1 A armadilha do "lembrete de assembleia" — resolvida por fronteira de tipo, não por subtipo

**Achado do acervo:** "LEMBRETE AGE 04.02.2026" é, pelo conteúdo (data, hora, local, pauta),
convocação — não aviso social. Não existe, no lote sondado, um arquivo rotulado "Edital" para essa
mesma assembleia: o lembrete pode ser o único registro digital do que convocou os condôminos.

**Decisão: classificar pelo efeito jurídico do conteúdo, nunca pelo nome do arquivo.** Regra dura
de reconhecimento, para humano e para classificador automático: se o texto contém elemento de
convocação — data/hora/local da assembleia **e** pauta (ordem do dia), com ou sem a fórmula "1ª/2ª
convocação" — o documento é `edital_convocacao`, **mesmo que o título diga "lembrete", "aviso" ou
"comunicado"**. Um "aviso de que a churrasqueira reabriu" não tem pauta de assembleia nem
data/hora/local de convocação — fica `comunicado`. Mesmo padrão de "classifique o artefato pelo
efeito, não pelo rótulo" já usado em `condominio-documentos` §12-bis para distinguir proposta
comercial de comunicado que a resume; **na dúvida, classificar como `edital_convocacao`** — falha
para o lado de maior efeito jurídico, não para o lado cômodo.

**Por que importa de verdade:** **CC art. 1.354** — a assembleia não pode deliberar se todos os
condôminos não forem convocados. Se o "lembrete" é, na prática, o único artefato que prova a
convocação de uma unidade específica, ele precisa estar no tipo que o produto trata como prova de
convocação (vinculável a `assembleias.edital_documento_id`), não perdido dentro de um balde
genérico de avisos que ninguém audita para esse fim.

**O que não decido aqui:** se a convenção deste condomínio já fixa prazo mínimo entre convocação e
assembleia (CC art. 1.334, III é supletivo — `condominio-legal` §6, "a convenção prevalece").
Verificar o prazo real exige ler a convenção (bloqueada por OCR pendente, `inventario-acervo.md`)
— fica registrado como dependência, não como bloqueio desta decisão de taxonomia.

---

## 2. AGI — não é tipo novo, nem subtipo de documento. É valor de enum que falta em `assembleias.tipo`

**Pergunta:** AGI vira subtipo de ata, tipo próprio, ou a taxonomia ganha campo
`especie_assembleia`?

**Resposta: o campo já existe — é `assembleias.tipo`, hoje `enum tipo_assembleia` com
`('ago','age','conselho_fiscal')` (`docs/schema.md` linha do `create type`). Falta o valor `agi`.**
Não crio tipo de documento novo nem subtipo dentro de `tipos_documento`: o artefato "ata de
assembleia" continua sendo um único `codigo='ata_assembleia'` — a migração de seed já renomeou o
`nome` para "Ata de assembleia (AGO/AGE/AGI)", o que estava certo em antecipação, mas ficou sem o
suporte estrutural (o enum) que dá esse nome sentido. A espécie jurídica da assembleia é
propriedade da **assembleia**, não do documento que a registra — mesma separação de
responsabilidade que já existe para AGO/AGE hoje (`assembleias.tipo`, com `ata_documento_id` e
`edital_documento_id` apontando para documentos cuja `visibilidade` é decidida por tipo).

**O que entra:** `agi` como quarto valor de `tipo_assembleia`. `deliberacoes` de uma AGI (eleição
do primeiro síndico, aprovação do regimento, instalação em si) seguem o mesmo modelo de âncora de
citação (`documento_id + pagina + trecho_literal`) já usado para AGO/AGE — nenhuma tabela nova.

**O que sai:** a hipótese de subtipo dentro de `tipos_documento` (rejeitada porque duplicaria uma
distinção que a `assembleias.tipo` já existe para fazer) e a hipótese de tipo de documento
`ata_agi` isolado (rejeitada porque o pipeline de ingestão, OCR e citação da ata de instalação é
idêntico ao de qualquer outra ata — só a leitura jurídica do evento muda).

**Fundamento e o que fica de fato em aberto (escalar, não decidir aqui):** o Código Civil
(arts. 1.331–1.358, conferido em `condominio-legal`) não nomeia "Assembleia Geral de Instalação"
— trata só de AGO (art. 1.350) e AGE (art. 1.355). "AGI" é nome de mercado para a assembleia que
formaliza a instituição do condomínio após a entrega (habite-se), tipicamente convocada pela
incorporadora/construtora antes de haver síndico eleito, cuja disciplina de fundo está mais perto
da Lei 4.591/64 (instituição e primeira administração, arts. 1º–9º) do que do Capítulo VII do CC —
matéria que a skill `condominio-legal` declara explicitamente **fora do seu escopo atual**
("Não cobre: ... incorporação"). **Isso não bloqueia esta decisão de taxonomia** (o valor de enum
e o modelo de citação não dependem do quórum exato da AGI), mas bloqueia qualquer alerta futuro
que precise validar quórum de uma AGI contra a convenção — sinalizo ao orquestrador que
`condominio-legal`, "em construção", precisa cobrir isso antes de o motor de alertas tratar
deliberação de AGI como tratou até agora AGO/AGE.

---

## 3. Resumo de assembleia × ata formal — decisão de tipo **e** de regra de citação, não de visibilidade

**Pergunta:** como impedir que o resumo seja citado como se fosse a ata?

**Resposta: tipo novo `resumo_assembleia` (16º) + regra de citação em `rag-citacao-juridica-ptbr`
— visibilidade não muda nada aqui**, porque resumo e ata têm a mesma audiência (autenticado, todo
morador) e o problema não é quem vê, é o que o sistema deixa **citar como prova de decisão**.

**Por que tipo, e não só um rótulo de UI:** a citação estruturada do SPEC (§4) e da skill
`rag-citacao-juridica-ptbr` (`Citacao.tipo`) é tipada — `'ata' | 'comunicado' | 'balancete' |
...`. Sem um valor próprio, um resumo entra como `'comunicado'` ou pior, é confundido com
`'ata'` na hora de rankear "o que foi decidido em X" (classe **factual-documental**, §2 daquela
skill). Precisa existir uma diferença que o motor de ranking e a UI possam ler sem depender de
prompt lendo o texto e "percebendo" que é informal — a mesma razão pela qual, em `condominio-legal`,
a fórmula ritual de abertura de ata ("aos [dia] dias do mês de...", "secretariada por") é sinal
de reconhecimento e não está presente em nenhum dos três resumos do acervo real.

**O que entra:**

- `tipos_documento.codigo = 'resumo_assembleia'`, autenticado, retenção permanente (mesma lógica
  de auditoria da ata — barato manter, e é evidência de divergência caso o resumo prometa algo que
  a ata registrada não confirme).
- Metadado `assembleia_id` (nullable — preenchido na conferência humana, SPEC §3 item 5, por
  proximidade de data) e `substitui_documento_id` (nullable, aponta para a ata quando ela é
  publicada depois).
- **Regra de citação (para quem mantém `rag-citacao-juridica-ptbr`, fora do meu escopo de
  arquivo — sinalizo, não edito):**
  1. `Citacao.tipo` ganha o valor `'resumo_assembleia'`.
  2. Toda citação desse tipo carrega selo fixo, diferente do selo de "resumo gerado por IA" (§6
     daquela skill): **"Resumo da administração · não é a ata oficial"** — porque aqui quem
     resume é a gestão, não o modelo, e o disclaimer errado banaliza os dois problemas como se
     fossem um só.
  3. `deliberacoes.documento_id` **nunca** aponta para um documento `resumo_assembleia` — só para
     `ata_assembleia`. Isso não impede indexar e citar o resumo em busca livre; impede que ele vire
     a âncora jurídica de uma deliberação, que é o dano concreto que a pergunta do brief descreve.
  4. Quando ata e resumo do mesmo `assembleia_id` estão ambos indexados e respondem à mesma
     pergunta factual-documental, a resposta prioriza o trecho da ata; se só o resumo responde,
     cita o resumo com o selo do item 2 — nunca omite a diferença silenciosamente.

**O que sai:** a ideia de resolver isso só na visibilidade (rejeitada — ambos são autenticados,
mesma audiência) e a ideia de tratar resumo como subtipo de `comunicado` (rejeitada — perderia o
metadado `assembleia_id`/`substitui_documento_id` que o mecanismo de citação precisa, e teria a
mesma armadilha de tipagem fraca do `Citacao.tipo` acima).

---

## 4. Cotação de fornecedor concorrente — confirma R1–R5 já registrados, acrescenta o pós-decisão

**Pergunta:** `conselho` está certo antes da decisão? O que muda depois?

**Resposta: sim, já está decidido e fundamentado** — `condominio-documentos` §12-bis, com parecer
em `docs/juridico/pareceres/2026-09-04-visibilidade-cotacoes.md`. Não redecido R1–R5. O gap real
era só a segunda metade da pergunta, que R1–R5 não cobriam: **o que muda quando a assembleia
aprova uma das propostas.**

**R6 — Resposta: a visibilidade do arquivo da proposta não muda. O que muda é qual artefato passa
a carregar a informação para o morador.**

1. **A proposta vencedora continua `conselho`.** A razão de R1 (CPF, telefone, assinatura e
   ART/CREA do representante do fornecedor — dado pessoal de terceiro que não é condômino) não
   desaparece com a decisão. Promover o arquivo a `autenticado` só porque "ganhou" trocaria a
   visibilidade por motivo estranho ao dado que ela protege — mesmo erro de raciocínio que R1 já
   rejeitou explicitamente para "preço é sigiloso".
2. **A proposta perdedora continua `conselho`, para sempre.** Nenhuma decisão futura devolve
   relevância pública a ela; segue como prova de concorrência para auditoria (SPEC §5.3, alerta de
   "cotação ausente") e para o próprio conselho fiscal revisitar a escolha.
3. **O que o morador passa a ver é a ata.** A deliberação que aprova a contratação vira uma linha
   em `deliberacoes` (documento_id = a ata, `autenticado`), com `valor_autorizado_centavos` e
   trecho literal — e o `contrato` resultante (`tipos_documento.contrato`, já autenticado por
   padrão) referencia o `fornecedor_id` vencedor. **O agregado sobe para autenticado através da
   ata e do contrato, nunca fazendo o PDF da cotação subir.** É o mesmo padrão de R2 (inadimplência
   e cotação seguem a régua "agregado para o morador, íntegra para a gestão"), estendido no tempo:
   a decisão da assembleia não é evento que promove um documento — é o evento que **cria um
   documento novo**, com visibilidade própria, que expõe o suficiente.

**Sobre o direito à informação (STJ REsp 2.050.372, `condominio-legal` §3):** manter a cotação em
`conselho` para sempre não fecha o direito individual de inspecionar documento relativo à
administração — esse direito é exercido pedindo o documento ao síndico/administradora fora do
Breeze, se o condômino especificamente quiser ver a proposta perdedora. O produto não é o único
canal de exercício desse direito; ele oferece o que a maioria dos moradores precisa (saber que
houve concorrência e por quanto) sem replicar dado pessoal de terceiro para toda a base de
usuários autenticados. Isso é leitura de uma decisão já registrada, não uma decisão nova de
visibilidade — não estou reabrindo o parecer de `juridico-lgpd`, só documentando a consequência
temporal que ele não havia coberto.

**O que entra:** R6 acima, como adendo à §12-bis da skill.
**O que sai:** nada — R1–R5 permanecem como estavam.

---

## 5. Documentos de entrega de obra e demonstrativo de cota — dois tipos novos, não um guarda-chuva único

**Pergunta:** Manual do Proprietário, Habite-se, formulário de garantia e demonstrativo de cota —
um tipo cada, ou um guarda-chuva "documento da construtora"?

**Resposta: guarda-chuva para os três primeiros (`documento_construtora`, 17º); tipo próprio para
o demonstrativo de cota (`demonstrativo_cota`, 18º). Não é a mesma família.**

**Por que os três primeiros cabem juntos:** Habite-se, Manual do Proprietário e formulário de
assistência técnica compartilham periodicidade (um evento só, na entrega — "V00" do manual e
"-25-" do processo do habite-se confirmam isso, `inventario-acervo.md`), produtor (a construtora,
não a gestão do condomínio) e função para o morador (entender o que foi entregue e como acionar
garantia) — três eixos que a taxonomia já usa para agrupar (ex.: laudos técnicos, §10, agrupa
AVCB/SPDA/elevador/cisterna/gás pelos mesmos três eixos, apesar de normas e periodicidades
distintas por subtipo). Criar três `codigo` para um volume esperado de poucas unidades por
condomínio não paga o custo de manutenção; o metadado `subtipo` resolve a diferenciação que a
busca por faceta precisa.

**Por que o demonstrativo de cota não entra no mesmo balde:** tem produtor diferente (gestão/
administradora, não construtora), é recorrente (mensal, com `competencia`) e tem função diferente
(explicar rateio, não documentar entrega/garantia) — os mesmos três eixos, resultado oposto. Além
disso, é financeiro o bastante para merecer o mesmo piso de retenção da família
balancete/previsão orçamentária (permanente, para comparabilidade histórica e para o risco 4 do
SPEC §8 — divergência entre o publicado e o balancete real), enquanto documento de construtora não
tem essa razão de retenção — a dele é a garantia (ver abaixo).

**Metadado que amarra ao momento do condomínio:** `documento_construtora.subtipo` inclui
`habite_se | manual_proprietario | formulario_garantia`, mais `construtora_cnpj/razao_social` e,
quando aplicável, `vigencia_garantia_meses` por item coberto — **inferência de prática de mercado,
não confirmada em norma primária nesta pesquisa**: entendo que o **CC art. 618** (responsabilidade
do empreiteiro por solidez e segurança da obra por prazo de 5 anos) é o fundamento típico da
garantia estrutural do imóvel, mas esse artigo está no título "Da Empreitada", **fora do recorte
de `condominio-legal`** (que cobre só arts. 1.331–1.358 e declara explicitamente que não cobre
incorporação/contrato de construção). **Marco `[VERIFICAR]` e sinalizo ao orquestrador**: se o
Breeze for tratar prazo de garantia como dado estruturado (para um alerta futuro do tipo "garantia
de item X vence em Y"), isso precisa de uma leitura jurídica que hoje não existe em nenhuma skill
carregada — não é matéria de `condominio-legal` no escopo atual, nem minha, sem fonte primária
lida nesta sessão.

**Visibilidade — não decido, registro o que caberia escalar:** os três documentos de construtora
não carregam nome de morador nem CPF; em princípio são tão impessoais quanto convenção e
regimento. **Não os marco como `publico`** porque isso contrariaria D2/§7 do SPEC ("só convenção e
regimento são públicos") sem que eu tenha mandato para reabrir essa regra — decisão de visibilidade
é de `juridico-lgpd`. Registro como candidato a exceção, para o orquestrador decidir se vale
levantar.

**O que entra:** `documento_construtora` (17º, guarda-chuva com subtipo) e `demonstrativo_cota`
(18º, tipo próprio, com `unidade_id` nullable — se preenchido, força `restrito`, mesma régua de
"dado individualizado por unidade" já usada em notificação/multa e inadimplência).
**O que sai:** a hipótese de um guarda-chuva único para os quatro documentos (rejeitada — produtor,
periodicidade e retenção divergem em dois eixos de três).

---

## 6. Achado menor, fora das 5 perguntas: material de apoio de assembleia

`Apresentação Reunião Geral - 12.03.2026.pdf` (slide, 11 páginas, baixo texto) não é ata, não é
edital, não é resumo — é material de apoio distribuído antes/durante a reunião, sem redação de
deliberação nem fórmula ritual. Tipo novo, leve: `material_apoio_assembleia` (19º), autenticado,
retenção permanente (mesma lógica de auditoria da ata — barato manter, referência de "o que foi
mostrado" em caso de disputa sobre o que a assembleia realmente discutiu), metadado
`assembleia_id` nullable. Não abre discussão própria porque o volume no acervo real é de um único
documento; registrado aqui para não ficar sem tipo caso apareça de novo.

---

## Tabela pronta para seed — só tipos novos ou alterados

`eng-supabase` aplica; esta tabela é a especificação, não a migração. Ordem escolhida para não
exigir renumerar as linhas existentes (`ordem` das 14 linhas atuais fica como está).

| codigo | nome | visibilidade_padrao | metadados obrigatórios | retenção | sinais de reconhecimento |
|---|---|---|---|---|---|
| `comunicado` **(alterado — escopo)** | Comunicado avulso | `autenticado` | data de emissão; remetente; **categoria** (`financeiro\|operacional\|institucional`); `unidade_destinataria` nullable (preenchida → força `restrito`) | 24 meses (decisão de produto, mantida) | Curto (1–3 pág.), "informamos"/"comunicamos aos senhores condôminos", assinado pela gestão. **Nunca** classificar aqui se houver data/hora/local de assembleia + pauta — vai para `edital_convocacao` mesmo que o título diga "lembrete" ou "aviso" (§1.1) |
| `comunicado_governanca` **(novo)** | Comunicado de governança (posse/renúncia/apresentação) | `autenticado` | `papel_afetado` (`sindico\|subsindico\|conselho\|administradora`); `evento` (`posse\|renuncia\|apresentacao\|substituicao`); vínculo a `fornecedores.id` **quando o evento é do síndico terceirizado (D3)** ou a `papeis.id` quando é de pessoa com conta; data efetiva | Permanente (mesma lógica de atas — evidência de mandato, CC art. 1.348 VIII / 1.349) | "Carta de apresentação", "venho comunicar minha renúncia/saída do cargo de síndico", "assumo a gestão a partir de" |
| `resumo_assembleia` **(novo)** | Resumo de assembleia (não oficial) | `autenticado` | `assembleia_id` nullable; `data_assembleia_referida`; `substitui_documento_id` nullable (aponta para a ata quando publicada) | Permanente | "Resumo da assembleia", "principais pontos", ausência da fórmula ritual de abertura de ata ("aos [dia] dias do mês de...", "secretariada por"), sem lista de presença formal, circula antes da ata |
| `material_apoio_assembleia` **(novo)** | Material de apoio de assembleia | `autenticado` | `assembleia_id` nullable; data | Permanente | Formato slide/apresentação, pouco texto corrido, título "Apresentação Reunião/Assembleia" + data |
| `demonstrativo_cota` **(novo)** | Demonstrativo de composição de cota | `autenticado` (⚠ `restrito` se `unidade_id` preenchida) | `competencia` (dia 1); `unidade_id` nullable; rubricas presentes (ordinária/extraordinária/fundo de reserva/rateio específico) | Permanente (mesma régua de balancete/previsão — comparabilidade histórica) | "Composição da cota", "demonstrativo de cota condominial", tabela rubrica × valor, título com mês/ano |
| `documento_construtora` **(novo)** | Documento da construtora / entrega de obra | `autenticado` | `subtipo` (`habite_se\|manual_proprietario\|formulario_garantia`); `construtora_cnpj`/razão social; `numero_processo` (habite-se); `vigencia_garantia_meses` nullable por item `[VERIFICAR — CC art. 618 é inferência, fora do escopo confirmado de condominio-legal]` | Permanente (produto); prazo de garantia real ainda não fundamentado em norma lida | Habite-se: "certificado de conclusão", "processo nº", órgão municipal. Manual: "manual do proprietário", versão "V0x", extenso. Formulário: "assistência técnica"/"solicitação de garantia", campos em branco, papel timbrado da construtora |

**Fora da tabela de seed, porque não é linha de `tipos_documento`:** o valor `agi` entra em
`public.tipo_assembleia` (enum, `docs/schema.md`), não na tabela de domínio — ver §2.

---

## O que fica em aberto (não decidido aqui, por não ser meu escopo ou por faltar fonte)

1. **Quórum e disciplina jurídica específica da AGI** — `condominio-legal` não cobre incorporação;
   sinalizado ao orquestrador (§2).
2. **Prazo de garantia decenal/estrutural (CC art. 618) e por item do Manual do Proprietário** —
   fora do recorte confirmado de qualquer skill carregada nesta sessão; marcado `[VERIFICAR]` (§5).
3. **Habite-se como candidato a exceção da regra "só convenção e regimento são públicos"** —
   registrado, não decidido; é pergunta de `juridico-lgpd` (§5).
4. **Atualização de `rag-citacao-juridica-ptbr`** (`Citacao.tipo` e regra de precedência
   ata-sobre-resumo) — fora do meu escopo de arquivo; especificado em §3 para quem mantém aquela
   skill.
5. **Prazo mínimo de convocação deste condomínio** — depende da convenção, hoje bloqueada por OCR
   pendente (§1.1); não bloqueia a decisão de tipo, bloqueia a validação de um caso concreto.
