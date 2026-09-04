# Decisões de domínio — plano de contas

Entradas curtas que registram uma decisão de modelagem contábil já pesquisada, para não repetir
a pesquisa. Não é glossário — é log de decisão. Ver skill `condominio-plano-de-contas` para o
plano em si.

## "Uso de fundo de reserva/obras" não é subgrupo de despesa próprio

**Pergunta:** existe conta de despesa para "saída do fundo" (ex.: `2.12 Uso de fundos`)?
**Resposta: não.** Uso de fundo é a mesma despesa finalística (obra, bomba, elevador) paga com
recurso de origem diferente — o "de onde saiu o dinheiro" é ortogonal ao "o que foi comprado".
Uma conta genérica de "uso de fundo" mistura naturezas de despesa incompatíveis num rótulo só,
destrói a granularidade do plano e diverge do balancete real da administradora (skill
`condominio-plano-de-contas` §8, alerta de espelhamento).

**Modelagem correta:** o lançamento entra na conta finalística já existente (2.3.x manutenção,
2.4.x elevadores, 2.10.x obras etc.), com `lancamentos.fundo` (`docs/schema.md` linha 875)
marcando a origem do recurso — atributo do lançamento, não da conta. `lancamentos.fundo` já
existe no schema independente de `conta_id`, então isso é avaliável sem conta sintética.

**Gap real encontrado:** o alerta "fundo sem ata" (SPEC §5.3) está fiado em
`contas.exige_deliberacao`, flag fixa na conta (`docs/schema.md` linha 730, 739). Isso força a
existência de uma conta "marcada" para o alerta disparar — e foi o que levou à criação de
`2.12` como gambiarra de seed. **Isso é questão de arquitetura do motor de alertas, não de plano
de contas** — encaminhado ao orquestrador/`eng-supabase`: considerar avaliar o alerta por
`lancamentos.fundo <> 'nenhum' AND deliberacao_id IS NULL` (já indexado,
`lancamentos_fundo_idx`), independente da conta debitada.

**Prática de mercado observada** [VERIFICAR — sem fonte primária]: administradoras costumam
apresentar a movimentação do fundo em demonstrativo à parte (saldo anterior + aportes +
rendimento − utilizações = saldo atual), não como despesa do resultado operacional do mês.
