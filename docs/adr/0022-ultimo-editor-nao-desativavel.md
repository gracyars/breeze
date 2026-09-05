# ADR-0022 — O último `editor` vigente não pode ser desativado

> Achado **V10** do `auditor-rls`. Não é vazamento: é **indisponibilidade irreversível**.

## Contexto

Com editora única (D4), a `editor` pode desativar a si mesma — `pessoas.ativa = false` — ou deixar
o próprio mandato expirar em `papeis`. Depois disso não há quem reverta: `service_role` não tem
`UPDATE` em `pessoas` nem em `papeis` (decisão deliberada do ADR-0012, item 6), e toda escrita
nessas tabelas exige `app.eh_editor()`, que acabou de virar falso.

O sistema não vaza nada. Ele simplesmente **fecha para sempre**, com o acervo e o financeiro do
condomínio dentro. Isso é o Risco §8.5 (bus factor = 1) na sua forma mais boba: não é a pessoa que
some, é um `UPDATE` de uma linha.

Vale notar que **o desenho está certo** — `service_role` não alcançar `pessoas` é o que impede
escalada de privilégio pela chave de serviço. O problema não é o cadeado; é não haver piso.

## Decisão

**Trigger que impede a operação quando ela deixaria zero pessoas com papel `editor` vigente.**
Cobre os dois caminhos que produzem o mesmo estado (ADR-0021, matriz de caminhos):

| Caminho | Guarda |
|---|---|
| `UPDATE pessoas SET ativa = false` | rejeita se a pessoa tem `editor` vigente e é a última |
| `UPDATE papeis SET mandato_fim = <passado>` / `DELETE` | rejeita se encerraria o último `editor` vigente |
| `INSERT`/`UPDATE` que antecipe `mandato_inicio` no futuro | mesma contagem: "vigente" é `mandato_inicio <= hoje` e `mandato_fim` nulo ou futuro |

A mensagem de erro precisa **dizer a saída**, não só barrar: *"conceda o papel `editor` a outra
pessoa antes de encerrar este mandato"*. Trava sem saída indicada vira contorno criativo.

**Escape documentado, não escondido.** Existe um caminho legítimo em que a última editora precisa
sair: entrega de gestão, ou conta comprometida. Nos dois, a ordem correta é **conceder antes de
revogar** — e é isso que a trava força. Para o caso extremo em que nem isso é possível (perda total
de acesso), o caminho é o de D9: os códigos de recuperação impressos, guardados fora do sistema.
Se nem eles existirem, resta intervenção com privilégio de dono do banco, feita pelo `devops`,
registrada no runbook e **auditada** — nunca um `service_role` com permissão permanente para isso,
porque essa permissão é exatamente a escalada que o ADR-0012 fecha.

## Consequências

- Uma classe de falha irreversível deixa de existir. É o princípio da **D9** aplicado onde ele é
  barato: onde dá para tornar a falha impossível por construção, torna-se — em vez de documentar
  o cuidado e torcer.
- **Lock-in aceito, e é preciso ser honesto sobre ele:** nunca se remove o último editor. Se a
  conta da editora for comprometida, desativá-la exige antes promover outra pessoa — o que exige
  privilégio de editor, que é justamente o que o atacante tem. Mitigação real é a D9 (recuperar o
  acesso) mais a trilha do ADR-0013 (a ação do atacante fica registrada e encadeada), não esta
  trava. **Esta trava resolve o acidente, não o ataque** — e confundir as duas coisas seria pior
  que não tê-la.
- Reforça, na prática, a decisão pendente do Briefing §7 item 2 (quem mais é administrador no
  dia 1): com dois editores, o lock-in some e o ataque fica mais caro. A trava torna o custo de
  ter um só editor visível toda vez que alguém esbarra nela.
- Custo de implementação e de leitura: baixo. Duas guardas, uma contagem.

## Alternativas descartadas

- **Documentar o cuidado no runbook.** Mesma família de erro da D12 e do V1: proteção que depende
  de alguém lembrar. Aqui é pior, porque a consequência é irreversível e não silenciosa — é total.
- **Dar `UPDATE` em `pessoas`/`papeis` ao `service_role` como rede.** Abriria escalada de
  privilégio permanente pela chave de serviço para consertar um acidente raro. Troca ruim.
- **Conta de quebra-vidro permanente com papel `editor`.** Foi recusada na D9 ("sem segundo editor
  e sem conta de quebra-vidro por ora"). Uma credencial privilegiada parada é superfície de ataque
  contínua para cobrir um evento raro; e não seria testada, logo não funcionaria quando precisasse.
- **Exigir dois editores por constraint (mínimo de dois).** Contraria a D4 frontalmente e não é
  decisão do arquiteto — é decisão da dona do projeto (Briefing §7 item 2).
- **Reativação automática por rotina.** Rotina que devolve privilégio sozinha é a escalada de
  privilégio com outro nome.

## Status

Aceito, 2026-09-04. Registrado em `docs/04-DECISOES.md` como D15 (junto do ADR-0021).
Implementação com o `eng-supabase`; teste de negação com o `auditor-rls`
(desativar a última editora falha; desativar quando há duas, passa).
