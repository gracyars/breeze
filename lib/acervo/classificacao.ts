/**
 * Classificação determinística a partir do nome do arquivo.
 *
 * O ADR-0029 §3 item 5 pede **zero digitação no caminho feliz**: são 43
 * documentos e uma pessoa só; se cada um exigir digitar título, tipo e data, a
 * conferência morre de tédio antes do décimo. O nome de arquivo deste acervo é
 * estruturado o bastante para resolver a maior parte — `2215 - BREEZE AGE
 * 04.02.2026 site.pdf`, `PrestContas janeiro 2026.pdf` — e o que sobra a editora
 * corrige na tela.
 *
 * **Sem LLM** (ADR-0027): regra determinística é auditável, reproduzível e não
 * custa nada. Um modelo acertaria mais casos e erraria de formas imprevisíveis
 * em documento jurídico; aqui, quando a regra não sabe, ela diz que não sabe.
 *
 * As armadilhas abaixo vieram do acervo real, não de hipótese — cada `if` fora
 * de ordem produziria classificação errada em documento que existe.
 */

export interface Classificacao {
  tipo: string;
  titulo: string;
  /** `YYYY-MM-DD` quando o nome traz data. */
  dataDocumento: string | null;
  /** Mês de referência (dia 1) para balancete e demonstrativo. */
  competencia: string | null;
  /** `null` = usa o padrão do tipo. Preenchida só quando a regra tem motivo. */
  visibilidade: string | null;
  /** Por que caiu neste tipo — aparece na conferência, para a pessoa discordar. */
  motivo: string;
}

const MESES: Record<string, number> = {
  janeiro: 1, fevereiro: 2, março: 3, marco: 3, abril: 4, maio: 5, junho: 6,
  julho: 7, agosto: 8, setembro: 9, outubro: 10, novembro: 11, dezembro: 12,
};

function semAcento(texto: string): string {
  return texto.normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase();
}

/** `04.02.2026`, `12_03_26`, `2026-09-06` → `2026-02-04`. */
export function dataDoNome(nome: string): string | null {
  const comSeparador = nome.match(/(\d{2})[._-](\d{2})[._-](\d{2,4})/);
  if (comSeparador) {
    const [, dia, mes, anoBruto] = comSeparador;
    const ano = anoBruto.length === 2 ? `20${anoBruto}` : anoBruto;
    const data = `${ano}-${mes}-${dia}`;
    return Number(mes) >= 1 && Number(mes) <= 12 && Number(dia) <= 31 ? data : null;
  }
  return null;
}

/** `janeiro 2026`, `dez-2025` → `2026-01-01`. */
export function competenciaDoNome(nome: string): string | null {
  const normalizado = semAcento(nome);
  for (const [mes, numero] of Object.entries(MESES)) {
    const alvo = semAcento(mes);
    const padrao = new RegExp(`\\b${alvo.slice(0, 3)}[a-z]*[\\s._-]*(\\d{4})\\b`);
    const casamento = normalizado.match(padrao);
    if (casamento) {
      return `${casamento[1]}-${String(numero).padStart(2, "0")}-01`;
    }
  }
  return null;
}

/**
 * Título legível a partir do nome do arquivo.
 *
 * Tira a extensão, o código da administradora (`2215`, `22115`) e o sufixo
 * `site`, que não dizem nada ao morador e ocupam o começo da linha — que é onde
 * o olho procura o assunto.
 */
export function tituloDoNome(nome: string): string {
  return nome
    .replace(/\.pdf$/i, "")
    .replace(/^\d{4,6}\s*[-–]?\s*/, "")
    .replace(/[\s-]*\bsite\b\s*$/i, "")
    .replace(/\s*\(\d+\)\s*$/, "")
    .replace(/\s{2,}/g, " ")
    .trim();
}

export function classifica(caminho: string): Classificacao {
  const nome = caminho.split("/").pop() ?? caminho;
  const pasta = semAcento(caminho.slice(0, caminho.length - nome.length));
  const n = semAcento(nome);

  const base = {
    titulo: tituloDoNome(nome),
    dataDocumento: dataDoNome(nome),
    competencia: competenciaDoNome(nome),
    visibilidade: null as string | null,
  };

  // A ordem importa e cada linha abaixo é uma armadilha do acervo real.

  // "LEMBRETE – ASSEMBLEIA GERAL EXTRAORDINÁRIA – 04.02.2026" **é convocação**,
  // não comunicado: traz data, hora, local e pauta, e convocação tem efeito
  // jurídico (CC art. 1.354). O rótulo do arquivo não decide.
  if (/lembrete|convoca|edital/.test(n)) {
    return { ...base, tipo: "edital_convocacao", motivo: "nome indica convocação de assembleia" };
  }

  // "RESUMO DA ASSEMBLEIA" circula antes da ata registrada e não é a ata. Tem de
  // vir ANTES da regra de ata, senão vira ata e passa a poder ancorar deliberação.
  if (/resumo.*(assembleia|reuniao)/.test(n)) {
    return { ...base, tipo: "resumo_assembleia", motivo: "é resumo da administração, não a ata" };
  }

  if (/apresentacao.*(reuniao|assembleia)/.test(n)) {
    return {
      ...base,
      tipo: "material_apoio_assembleia",
      motivo: "material de apoio de assembleia",
    };
  }

  if (/\b(age|ago|agi)\b|assembleia geral/.test(n) || pasta.includes("atas")) {
    return { ...base, tipo: "ata_assembleia", motivo: "ata de assembleia" };
  }

  if (/convencao/.test(n)) {
    return {
      ...base,
      tipo: "convencao",
      visibilidade: "publico",
      motivo: "convenção — documento público por decisão (Briefing §7.1)",
    };
  }

  if (/regulamento interno|regimento/.test(n) || /^ri[\s-]/.test(n)) {
    return {
      ...base,
      tipo: "regimento",
      visibilidade: "publico",
      motivo: "regimento interno — documento público",
    };
  }

  if (/prestcontas|balancete/.test(n)) {
    return { ...base, tipo: "balancete", motivo: "balancete mensal da administradora" };
  }

  if (/previsao orcamentaria|orcamento/.test(n) && !pasta.includes("orcamentos")) {
    return { ...base, tipo: "previsao_orcamentaria", motivo: "previsão orçamentária" };
  }

  if (/composicao da cota|demonstrativo/.test(n)) {
    return { ...base, tipo: "demonstrativo_cota", motivo: "demonstrativo de composição da cota" };
  }

  if (/avcb|brigada|spda|laudo|atestado/.test(n)) {
    return { ...base, tipo: "laudo_tecnico", motivo: "laudo ou atestado técnico" };
  }

  if (/habite-se|manual do proprietario|assistencia tecnica/.test(n)) {
    return {
      ...base,
      tipo: "documento_construtora",
      motivo: "documento de entrega de obra / construtora",
    };
  }

  // Proposta comercial de concorrente não vira leitura de todo mundo enquanto a
  // assembleia não decidir — e continua fechada depois (decisão do domínio).
  if (pasta.includes("orcamentos") || /proposta|orcamento/.test(n)) {
    return {
      ...base,
      tipo: "documentacao_obra",
      visibilidade: "conselho",
      motivo: "cotação de fornecedor — proposta concorrente, visibilidade conselho",
    };
  }

  if (/procedimentos.*(reforma|obra)|reformas/.test(n)) {
    return { ...base, tipo: "documentacao_obra", motivo: "regra de obras e reformas" };
  }

  if (/renuncia|apresentacao|posse|sindico/.test(n)) {
    return {
      ...base,
      tipo: "comunicado_governanca",
      motivo: "comunicado de governança (posse, renúncia, apresentação)",
    };
  }

  if (pasta.includes("comunicado") || /comunicado|esclarecimento|aviso/.test(n)) {
    return { ...base, tipo: "comunicado", motivo: "comunicado avulso da gestão" };
  }

  return {
    ...base,
    tipo: "outros",
    motivo: "a regra não reconheceu o nome — classifique na conferência",
  };
}
