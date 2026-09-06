-- Breeze — F1: sinônimos que vêm do acervo real, não de suposição.
--
-- Achado que motivou esta migração: com o Regimento Interno já indexado (23 páginas, 31 chunks),
-- a busca léxica por **"posso ter cachorro?"** — que é a pergunta-exemplo do SPEC §4 e §6.2 —
-- devolve **zero resultados**. O documento nunca escreve "cachorro": o capítulo V se chama
-- "ANIMAIS DOMÉSTICOS" e o texto fala em "animais", "raças" e "coleira".
--
-- Isto não é um detalhe de vocabulário, é o modo de falha central da busca léxica: o morador
-- pergunta com a palavra dele e o documento responde com a palavra do cartório. Enquanto a metade
-- semântica está desligada (ADR-0027, D18), a tabela `sinonimos` é a única ponte — e ela só
-- funciona se for alimentada com o vocabulário REAL dos documentos, lido depois de indexar.
--
-- Método usado (repetível, e melhor que inventar sinônimo de cabeça): indexar o documento,
-- rodar as perguntas que o SPEC promete responder, e olhar quais voltam vazias. Cada linha abaixo
-- saiu de uma pergunta que falhou.
insert into public.sinonimos (termo, expansoes) values
  -- SPEC §6.2, placeholder rotativo: "posso ter cachorro?"
  ('cachorro',        array['cão', 'animal doméstico', 'animal', 'pet']),
  ('cão',             array['cachorro', 'animal doméstico', 'animal', 'pet']),
  ('gato',            array['animal doméstico', 'animal', 'pet']),
  ('pet',             array['animal doméstico', 'animal']),
  -- Espaços comuns: o morador chama pelo uso, o regimento pelo nome do espaço.
  ('festa',           array['salão de festas', 'salão gourmet', 'churrasqueira']),
  ('academia',        array['fitness', 'sala de ginástica']),
  ('mudança',         array['mudanças', 'transporte de móveis', 'elevador de serviço']),
  ('obra',            array['reforma', 'obras e reformas']),
  ('barulho',         array['ruído', 'perturbação do sossego', 'horário de silêncio']),
  ('bicicleta',       array['bicicletário', 'bike']),
  ('visita',          array['visitante', 'portaria', 'autorização de entrada']),
  ('multa',           array['penalidade', 'advertência', 'infração']),
  -- Financeiro: o vocabulário da administradora não é o do morador.
  ('boleto',          array['cota condominial', 'taxa condominial', 'cobrança']),
  ('conta',           array['balancete', 'prestação de contas', 'demonstrativo'])
on conflict (termo_normalizado) do nothing;

comment on table public.sinonimos is
  'RLS: leitura para todos (inclusive anon — a busca pública em convenção/regimento precisa); '
  'escrita só editor. Sem PII. Expansão de sinônimo acontece NA APLICAÇÃO (SPEC §4): Supabase '
  'gerenciado não dá acesso a $SHAREDIR para dicionário synonym/thesaurus. '
  'MANUTENÇÃO: linha nova aqui deve nascer de pergunta real que voltou vazia contra o acervo '
  'indexado — não de suposição sobre o que o morador diria. Ver 20260906120000.';
