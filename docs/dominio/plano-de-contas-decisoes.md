# Decisões de domínio — plano de contas

Entradas curtas que registram uma decisão de modelagem contábil já pesquisada, para não repetir
a pesquisa. Não é glossário — é log de decisão. Ver skill `condominio-plano-de-contas` para o
plano em si. Referências a `docs/schema.md` são por nome de tabela/coluna e título de seção,
nunca por número de linha — documento vivo, linha quebra em silêncio.

**Princípio de registro:** toda entrada aqui lista o que **entra** e o que **sai**, com o motivo
de cada um — nunca um resumo do que "mudou". Resumo perde a fronteira entre o que foi removido e
o que só mudou de uso, e é exatamente na fronteira que o próximo agente erra (ex.: apagar uma
coluna que só deixou de valer para um subconjunto de linhas).

## "Uso de fundo de reserva/obras" não é subgrupo de despesa próprio

**Pergunta:** existe conta de despesa para "saída do fundo" (ex.: `2.12 Uso de fundos`)?
**Resposta: não.** Uso de fundo é a mesma despesa finalística (obra, bomba, elevador) paga com
recurso de origem diferente — o "de onde saiu o dinheiro" é ortogonal ao "o que foi comprado".
Uma conta genérica de "uso de fundo" mistura naturezas de despesa incompatíveis num rótulo só,
destrói a granularidade do plano e diverge do balancete real da administradora (skill
`condominio-plano-de-contas` §8, alerta de espelhamento).

**Modelagem correta:** o lançamento entra na conta finalística já existente (2.3.x manutenção,
2.4.x elevadores, 2.10.x obras etc.), com `lancamentos.fundo` marcando a origem do recurso —
atributo do lançamento quando se trata de **despesa**, nunca da conta debitada.

**Decisão registrada:** virou **D12** em `docs/04-DECISOES.md`. O gap original não era de plano
de contas — era o alerta "fundo sem ata" (SPEC §5.3) apoiado em `contas.exige_deliberacao`, flag
fixa na conta, que forçava a existência de uma conta "marcada" para o alerta ter o que avaliar
(foi o que levou à conta sintética `2.12` no seed).

**O que sai e o que fica — a fronteira, não o resumo:**

- **Sai:** `contas.exige_deliberacao`. Era a flag que amarrava a regra a um conjunto fechado de
  contas. Sai porque qualquer despesa pode ser paga com fundo — a flag produzia falso negativo
  silencioso no gasto não previsto, que é o caso que mais importa fiscalizar. A conta sintética
  `2.12 Uso de fundos` sai junto, sem mais motivo de existir.
- **Fica:** `contas.fundo`, mas só faz sentido preenchida em conta de **receita** — 1.3.x
  (contribuição/rendimento do fundo de reserva), 1.4.x (idem, fundo de obras). Ali a natureza é
  estrutural, não depende de lançamento: uma conta de receita de fundo de reserva é, por
  definição, do fundo de reserva. Em conta de **despesa**, `contas.fundo` fica sempre `'nenhum'`
  — é isso que o comentário da coluna registra depois de D12.
- **Regra:** origem do recurso é atributo da **conta** quando é receita (só pode vir de um
  fundo); é atributo do **lançamento** quando é despesa (pode ser pago de qualquer fonte). A
  fiscalização do alerta "fundo sem ata" avalia o lado despesa, por isso olha o lançamento:
  `lancamentos.fundo <> 'nenhum' AND tipo = 'despesa' AND deliberacao_id IS NULL`, independente
  da conta debitada (índice `lancamentos_fundo_idx`, já existente e mantido).

Estado atual do schema: ver `docs/schema.md`, tabelas `contas` e `lancamentos`. Não citar mais
`contas.exige_deliberacao` como parte do modelo vigente — resíduo pré-D12 se aparecer em código
ou doc não atualizado. Não tratar `contas.fundo` como removida: ela segue preenchida nas contas
de receita 1.3.x/1.4.x; só nas contas de despesa é que vale `'nenhum'` sempre.

**Padrão geral (vale para outros alertas do SPEC §5.3):** fiscalização não pode depender de flag
de cadastro que o operador controla — quem quer escapar não marca a caixinha. Regra de alerta se
avalia sobre atributo do fato registrado (o lançamento, o anexo, o contrato), nunca sobre
metadado de conta. D12 já estende isso a "despesa sem comprovante" (ausência de anexo, não flag
"exige comprovante" na conta) e "cotação ausente" (valor do lançamento vs. limiar, não marcação
"conta que exige cotação").

**Prática de mercado observada** [VERIFICAR — sem fonte primária]: administradoras costumam
apresentar a movimentação do fundo em demonstrativo à parte (saldo anterior + aportes +
rendimento − utilizações = saldo atual), não como despesa do resultado operacional do mês.
