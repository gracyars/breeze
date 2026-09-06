-- Breeze — F1 corte C2 (hotfix): `documentos_select` deixa de reconsultar `documentos`.
--
-- ACHADO (reproduzido pelo orquestrador, stack local, commit a34e017 + migrações de C2):
-- `insert into public.documentos (...) returning id` dá 42501 ("new row violates row-level
-- security policy") para QUALQUER papel, inclusive editor com aal2 — mesmo `insert` sem
-- `returning` funciona, e um `select` da mesma linha num COMANDO seguinte enxerga normalmente.
--
-- CAUSA: `documentos_select` chamava `app.documento_visivel(id)`, que faz
--   `select exists (select 1 from public.documentos d where d.id = p_documento_id and (...))`
-- — ou seja, RECONSULTA `public.documentos` para decidir sobre uma linha de `public.documentos`.
-- `INSERT ... RETURNING` avalia a policy de SELECT sobre a linha recém-criada DENTRO DO MESMO
-- COMANDO (o mesmo vale para `UPDATE ... RETURNING`, que também precisa passar pela policy de
-- SELECT para decidir o que devolver — não só pela de UPDATE). Sob MVCC, uma subconsulta
-- disparada pelo mesmo comando não enxerga a própria linha que esse comando está inserindo
-- (cid da nova linha == cid do comando corrente) — por isso o `exists` dá falso e a policy nega,
-- e por isso um comando NOVO (select subsequente) já enxerga.
--
-- Esta é a MESMA classe de defeito do ADR-0023 ("predicado de autorização deve ser local"),
-- espécie MODAL: `documento_visivel` não precisa reconsultar `documentos` para decidir sobre a
-- própria linha avaliada — `status`, `visibilidade` e `id` já estão na linha. A releitura não
-- protegia nada (ninguém grava `documentos` "por fora" da própria linha para este predicado);
-- só introduziu a não-localidade que quebra RETURNING. Nível 0 do ADR-0023: tornar local.
--
-- `app.documento_visivel(uuid)` PERMANECE intacta e é a entrada certa para quem pergunta pela
-- visibilidade de um documento DE FORA da tabela `documentos` — storage.objects (bucket
-- 'documentos') e `deliberacoes` (quando não há página específica) são exemplos legítimos:
-- ali a releitura de `documentos` é uma tabela DIFERENTE da que está sendo escrita, então não há
-- conflito de comando/CID. Só a policy de `documentos` sobre `documentos` precisa da forma local.
--
-- VARREDURA DA MESMA CLASSE (pedida pelo orquestrador) — resultado abaixo, nenhuma outra policy
-- corrigida nesta migração porque nenhuma outra tem o defeito:
--
--   documento_paginas_select / chunks_select: chamam app.pagina_visivel -> app.nivel_efetivo,
--     que reconsulta documento_paginas (self, para chunks é tabela ALHEIA; para documento_paginas
--     é self). MAS documento_paginas e chunks não têm policy de INSERT/UPDATE para nenhum papel
--     de usuário — só o worker escreve, via service_role, que tem BYPASSRLS e nunca avalia
--     policy nenhuma (20260904120000, "service_role bypassa RLS"). O papel que legitimamente
--     escreve nessas duas tabelas nunca passa pela policy — não há INSERT/UPDATE ... RETURNING
--     para quebrar. Não corrigido: não haveria o que corrigir sem mudar quem escreve.
--
--   pessoas_select: `id = app.pessoa_atual() or app.eh_gestao()`. app.pessoa_atual() reconsulta
--     pessoas (self), mas só no primeiro operando, e esse operando por si só JÁ é equivalente a
--     um predicado local (auth_user_id é UNIQUE em pessoas — 20260904120300): "id = pessoa_atual()"
--     e "auth_user_id = auth.uid() and ativa" descrevem a MESMA linha. Ou seja, o único caso onde
--     a releitura poderia colidir com uma linha recém-escrita no mesmo comando (editor
--     atualizando a PRÓPRIA linha) é precisamente o caso em que o operando alternativo, que não
--     toca `pessoas`, já resolve para true — o `or` nunca depende da leitura não-local para este
--     caso. Não corrigido por não ter efeito observável; não é o mesmo defeito.
--
--   papeis_select: `pessoa_id = app.pessoa_atual() or app.eh_gestao()`. app.eh_gestao() ->
--     app.tem_papel() reconsulta `papeis` (self) e `pessoas` (alheia). Mesmo raciocínio de
--     pessoas_select: o único cenário de colisão de comando é o editor escrevendo a PRÓPRIA linha
--     de papeis, e nesse cenário `pessoa_id = app.pessoa_atual()` (que só toca `pessoas`, tabela
--     alheia e não afetada pela escrita em `papeis`) já é true sozinho. Não corrigido pelo mesmo
--     motivo.
--
--   cobrancas_select, lancamentos_select, lancamento_anexos_select, assembleias_select,
--   deliberacoes_select, contas_select, fornecedores_select, contratos_select,
--   periodos_fechados_select, orcamento_select, unidades_select, vinculos_select,
--   documento_unidades_select, tipos_documento_select: nenhuma reconsulta a PRÓPRIA tabela.
--   Todas resolvem por coluna local (`unidade_id`, `status`, etc.) combinada com funções que
--   consultam outras tabelas (`vinculos`, `papeis`, `pessoas`) — nunca a tabela que está sendo
--   escrita. Sem o defeito.
--
-- Conclusão da varredura: `documentos` era o ÚNICO caso real, porque era o único predicado cujo
-- ÚNICO caminho de decisão depende de reconsultar a própria tabela sem alternativa local no `or`.

drop policy documentos_select on public.documentos;

create policy documentos_select on public.documentos
  for select to anon, authenticated
  using (
    app.eh_gestao()
    or (status = 'publicado' and app.nivel_visivel(visibilidade, id))
  );

comment on policy documentos_select on public.documentos is
  'LOCAL desde 2026-09-06 (hotfix RETURNING): antes chamava app.documento_visivel(id), que '
  'reconsultava documentos e quebrava INSERT/UPDATE ... RETURNING (a policy de SELECT roda no '
  'mesmo comando, que ainda não vê a própria linha nova/alterada sob MVCC). Mesmo alcance de '
  'autorização de antes — só forma local (ADR-0023, nível 0): eh_gestao() vê tudo; os demais só '
  'publicado + nível visível, lendo status/visibilidade/id da PRÓPRIA linha. '
  'app.documento_visivel(uuid) continua existindo, intacta, para quem pergunta de FORA de '
  'documentos (storage.objects, deliberacoes) — ali a releitura é de tabela alheia, não é o '
  'mesmo defeito.';

-- `anon` passa a chamar app.nivel_visivel(...) DIRETO (antes só por dentro de
-- app.documento_visivel/app.pagina_visivel, ambas SECURITY DEFINER — a checagem de EXECUTE de
-- uma chamada aninhada dentro de SECURITY DEFINER roda com o privilégio do DONO da função, não
-- do chamador original, por isso `anon` nunca precisou de GRANT direto em nivel_visivel até
-- agora). Chamar direto da policy exige GRANT explícito, senão documento público vira 42501 para
-- anon — regressão que a comparação antes/depois abaixo pegaria. Grant só formaliza um caminho
-- que já era alcançável por anon através de documento_visivel; não amplia o que nivel_visivel
-- pode fazer nem quem pode decidir com ele.
grant execute on function app.nivel_visivel(public.visibilidade_documento, uuid) to anon;

comment on function app.documento_visivel(uuid) is
  'Entrada para visibilidade de ARQUIVO/linha inteira DE FORA de documentos — storage.objects '
  '(bucket ''documentos'') e deliberacoes (documento sem página específica). Não é mais chamada '
  'pela policy de SELECT de documentos (ver documentos_select, 2026-09-06): ali reconsultar a '
  'própria tabela dentro do mesmo predicado quebrava INSERT/UPDATE ... RETURNING (MVCC/CID). A '
  'lógica é idêntica, só inlined localmente onde a tabela avaliada é a própria documentos.';
