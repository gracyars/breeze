export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  graphql_public: {
    Tables: {
      [_ in never]: never
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      graphql: {
        Args: {
          extensions?: Json
          operationName?: string
          query?: string
          variables?: Json
        }
        Returns: Json
      }
    }
    Enums: {
      [_ in never]: never
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
  public: {
    Tables: {
      alertas: {
        Row: {
          chave_dedupe: string
          competencia: string | null
          conta_id: string | null
          contrato_id: string | null
          criado_em: string
          detalhe: Json
          fornecedor_id: string | null
          id: string
          lancamento_id: string | null
          resolucao: string | null
          resolvido_em: string | null
          resolvido_por: string | null
          severidade: Database["public"]["Enums"]["severidade_alerta"]
          status: Database["public"]["Enums"]["status_alerta"]
          tipo: string
        }
        Insert: {
          chave_dedupe: string
          competencia?: string | null
          conta_id?: string | null
          contrato_id?: string | null
          criado_em?: string
          detalhe?: Json
          fornecedor_id?: string | null
          id?: string
          lancamento_id?: string | null
          resolucao?: string | null
          resolvido_em?: string | null
          resolvido_por?: string | null
          severidade: Database["public"]["Enums"]["severidade_alerta"]
          status?: Database["public"]["Enums"]["status_alerta"]
          tipo: string
        }
        Update: {
          chave_dedupe?: string
          competencia?: string | null
          conta_id?: string | null
          contrato_id?: string | null
          criado_em?: string
          detalhe?: Json
          fornecedor_id?: string | null
          id?: string
          lancamento_id?: string | null
          resolucao?: string | null
          resolvido_em?: string | null
          resolvido_por?: string | null
          severidade?: Database["public"]["Enums"]["severidade_alerta"]
          status?: Database["public"]["Enums"]["status_alerta"]
          tipo?: string
        }
        Relationships: [
          {
            foreignKeyName: "alertas_conta_id_fkey"
            columns: ["conta_id"]
            isOneToOne: false
            referencedRelation: "contas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "alertas_contrato_id_fkey"
            columns: ["contrato_id"]
            isOneToOne: false
            referencedRelation: "contratos"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "alertas_fornecedor_id_fkey"
            columns: ["fornecedor_id"]
            isOneToOne: false
            referencedRelation: "fornecedores"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "alertas_lancamento_id_fkey"
            columns: ["lancamento_id"]
            isOneToOne: false
            referencedRelation: "lancamentos"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "alertas_lancamento_id_fkey"
            columns: ["lancamento_id"]
            isOneToOne: false
            referencedRelation: "vw_lancamentos_com_comprovante"
            referencedColumns: ["lancamento_id"]
          },
          {
            foreignKeyName: "alertas_resolvido_por_fkey"
            columns: ["resolvido_por"]
            isOneToOne: false
            referencedRelation: "pessoas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "alertas_resolvido_por_fkey"
            columns: ["resolvido_por"]
            isOneToOne: false
            referencedRelation: "vw_pessoas_mascaradas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "alertas_tipo_fkey"
            columns: ["tipo"]
            isOneToOne: false
            referencedRelation: "tipos_alerta"
            referencedColumns: ["codigo"]
          },
        ]
      }
      assembleias: {
        Row: {
          ata_documento_id: string | null
          criado_em: string
          criado_por: string | null
          data: string
          edital_documento_id: string | null
          id: string
          local: string | null
          quorum_presente: number | null
          tipo: Database["public"]["Enums"]["tipo_assembleia"]
        }
        Insert: {
          ata_documento_id?: string | null
          criado_em?: string
          criado_por?: string | null
          data: string
          edital_documento_id?: string | null
          id?: string
          local?: string | null
          quorum_presente?: number | null
          tipo: Database["public"]["Enums"]["tipo_assembleia"]
        }
        Update: {
          ata_documento_id?: string | null
          criado_em?: string
          criado_por?: string | null
          data?: string
          edital_documento_id?: string | null
          id?: string
          local?: string | null
          quorum_presente?: number | null
          tipo?: Database["public"]["Enums"]["tipo_assembleia"]
        }
        Relationships: [
          {
            foreignKeyName: "assembleias_ata_documento_id_fkey"
            columns: ["ata_documento_id"]
            isOneToOne: false
            referencedRelation: "documentos"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "assembleias_ata_documento_id_fkey"
            columns: ["ata_documento_id"]
            isOneToOne: false
            referencedRelation: "vw_documentos_publicados"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "assembleias_criado_por_fkey"
            columns: ["criado_por"]
            isOneToOne: false
            referencedRelation: "pessoas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "assembleias_criado_por_fkey"
            columns: ["criado_por"]
            isOneToOne: false
            referencedRelation: "vw_pessoas_mascaradas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "assembleias_edital_documento_id_fkey"
            columns: ["edital_documento_id"]
            isOneToOne: false
            referencedRelation: "documentos"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "assembleias_edital_documento_id_fkey"
            columns: ["edital_documento_id"]
            isOneToOne: false
            referencedRelation: "vw_documentos_publicados"
            referencedColumns: ["id"]
          },
        ]
      }
      chunks: {
        Row: {
          criado_em: string
          documento_id: string
          embedding: string | null
          id: string
          ordem: number
          pagina_fim: number
          pagina_ini: number
          secao: string | null
          texto: string
          tokens: number | null
          tsv: unknown
          versao_embedding: number | null
          versao_pipeline: number
        }
        Insert: {
          criado_em?: string
          documento_id: string
          embedding?: string | null
          id?: string
          ordem: number
          pagina_fim: number
          pagina_ini: number
          secao?: string | null
          texto: string
          tokens?: number | null
          tsv?: unknown
          versao_embedding?: number | null
          versao_pipeline?: number
        }
        Update: {
          criado_em?: string
          documento_id?: string
          embedding?: string | null
          id?: string
          ordem?: number
          pagina_fim?: number
          pagina_ini?: number
          secao?: string | null
          texto?: string
          tokens?: number | null
          tsv?: unknown
          versao_embedding?: number | null
          versao_pipeline?: number
        }
        Relationships: [
          {
            foreignKeyName: "chunks_documento_id_fkey"
            columns: ["documento_id"]
            isOneToOne: false
            referencedRelation: "documentos"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "chunks_documento_id_fkey"
            columns: ["documento_id"]
            isOneToOne: false
            referencedRelation: "vw_documentos_publicados"
            referencedColumns: ["id"]
          },
        ]
      }
      cobrancas: {
        Row: {
          atualizado_em: string
          competencia: string
          criado_em: string
          data_pagamento: string | null
          documento_id: string | null
          id: string
          status: Database["public"]["Enums"]["status_cobranca"]
          unidade_id: string
          valor_centavos: number
          valor_pago_centavos: number
          vencimento: string
        }
        Insert: {
          atualizado_em?: string
          competencia: string
          criado_em?: string
          data_pagamento?: string | null
          documento_id?: string | null
          id?: string
          status?: Database["public"]["Enums"]["status_cobranca"]
          unidade_id: string
          valor_centavos: number
          valor_pago_centavos?: number
          vencimento: string
        }
        Update: {
          atualizado_em?: string
          competencia?: string
          criado_em?: string
          data_pagamento?: string | null
          documento_id?: string | null
          id?: string
          status?: Database["public"]["Enums"]["status_cobranca"]
          unidade_id?: string
          valor_centavos?: number
          valor_pago_centavos?: number
          vencimento?: string
        }
        Relationships: [
          {
            foreignKeyName: "cobrancas_documento_id_fkey"
            columns: ["documento_id"]
            isOneToOne: false
            referencedRelation: "documentos"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "cobrancas_documento_id_fkey"
            columns: ["documento_id"]
            isOneToOne: false
            referencedRelation: "vw_documentos_publicados"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "cobrancas_unidade_id_fkey"
            columns: ["unidade_id"]
            isOneToOne: false
            referencedRelation: "unidades"
            referencedColumns: ["id"]
          },
        ]
      }
      configuracoes: {
        Row: {
          atualizado_em: string
          atualizado_por: string | null
          chave: string
          descricao: string | null
          publica: boolean
          valor: Json
        }
        Insert: {
          atualizado_em?: string
          atualizado_por?: string | null
          chave: string
          descricao?: string | null
          publica?: boolean
          valor: Json
        }
        Update: {
          atualizado_em?: string
          atualizado_por?: string | null
          chave?: string
          descricao?: string | null
          publica?: boolean
          valor?: Json
        }
        Relationships: [
          {
            foreignKeyName: "configuracoes_atualizado_por_fkey"
            columns: ["atualizado_por"]
            isOneToOne: false
            referencedRelation: "pessoas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "configuracoes_atualizado_por_fkey"
            columns: ["atualizado_por"]
            isOneToOne: false
            referencedRelation: "vw_pessoas_mascaradas"
            referencedColumns: ["id"]
          },
        ]
      }
      contas: {
        Row: {
          aceita_lancamento: boolean
          ativa: boolean
          codigo: string
          codigo_administradora: string | null
          conta_pai_id: string | null
          criado_em: string
          fundo: Database["public"]["Enums"]["fundo"]
          id: string
          natureza: Database["public"]["Enums"]["natureza_conta"]
          nivel: number
          nome: string
          nome_administradora: string | null
        }
        Insert: {
          aceita_lancamento?: boolean
          ativa?: boolean
          codigo: string
          codigo_administradora?: string | null
          conta_pai_id?: string | null
          criado_em?: string
          fundo?: Database["public"]["Enums"]["fundo"]
          id?: string
          natureza: Database["public"]["Enums"]["natureza_conta"]
          nivel: number
          nome: string
          nome_administradora?: string | null
        }
        Update: {
          aceita_lancamento?: boolean
          ativa?: boolean
          codigo?: string
          codigo_administradora?: string | null
          conta_pai_id?: string | null
          criado_em?: string
          fundo?: Database["public"]["Enums"]["fundo"]
          id?: string
          natureza?: Database["public"]["Enums"]["natureza_conta"]
          nivel?: number
          nome?: string
          nome_administradora?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "contas_conta_pai_id_fkey"
            columns: ["conta_pai_id"]
            isOneToOne: false
            referencedRelation: "contas"
            referencedColumns: ["id"]
          },
        ]
      }
      contratos: {
        Row: {
          contrato_anterior_id: string | null
          criado_em: string
          criado_por: string | null
          deliberacao_id: string | null
          documento_id: string | null
          encerrado_em: string | null
          fornecedor_id: string
          id: string
          indice_reajuste: string | null
          objeto: string
          valor_mensal_centavos: number | null
          vigencia_fim: string | null
          vigencia_inicio: string
        }
        Insert: {
          contrato_anterior_id?: string | null
          criado_em?: string
          criado_por?: string | null
          deliberacao_id?: string | null
          documento_id?: string | null
          encerrado_em?: string | null
          fornecedor_id: string
          id?: string
          indice_reajuste?: string | null
          objeto: string
          valor_mensal_centavos?: number | null
          vigencia_fim?: string | null
          vigencia_inicio: string
        }
        Update: {
          contrato_anterior_id?: string | null
          criado_em?: string
          criado_por?: string | null
          deliberacao_id?: string | null
          documento_id?: string | null
          encerrado_em?: string | null
          fornecedor_id?: string
          id?: string
          indice_reajuste?: string | null
          objeto?: string
          valor_mensal_centavos?: number | null
          vigencia_fim?: string | null
          vigencia_inicio?: string
        }
        Relationships: [
          {
            foreignKeyName: "contratos_contrato_anterior_id_fkey"
            columns: ["contrato_anterior_id"]
            isOneToOne: false
            referencedRelation: "contratos"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "contratos_criado_por_fkey"
            columns: ["criado_por"]
            isOneToOne: false
            referencedRelation: "pessoas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "contratos_criado_por_fkey"
            columns: ["criado_por"]
            isOneToOne: false
            referencedRelation: "vw_pessoas_mascaradas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "contratos_deliberacao_id_fkey"
            columns: ["deliberacao_id"]
            isOneToOne: false
            referencedRelation: "deliberacoes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "contratos_documento_id_fkey"
            columns: ["documento_id"]
            isOneToOne: false
            referencedRelation: "documentos"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "contratos_documento_id_fkey"
            columns: ["documento_id"]
            isOneToOne: false
            referencedRelation: "vw_documentos_publicados"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "contratos_fornecedor_id_fkey"
            columns: ["fornecedor_id"]
            isOneToOne: false
            referencedRelation: "fornecedores"
            referencedColumns: ["id"]
          },
        ]
      }
      deliberacoes: {
        Row: {
          abstencoes: number | null
          assembleia_id: string
          chunk_id: string | null
          criado_em: string
          criado_por: string | null
          descricao: string
          documento_id: string | null
          id: string
          item: number
          pagina: number | null
          resultado: string
          trecho_literal: string | null
          valor_autorizado_centavos: number | null
          votos_contra: number | null
          votos_favor: number | null
        }
        Insert: {
          abstencoes?: number | null
          assembleia_id: string
          chunk_id?: string | null
          criado_em?: string
          criado_por?: string | null
          descricao: string
          documento_id?: string | null
          id?: string
          item: number
          pagina?: number | null
          resultado: string
          trecho_literal?: string | null
          valor_autorizado_centavos?: number | null
          votos_contra?: number | null
          votos_favor?: number | null
        }
        Update: {
          abstencoes?: number | null
          assembleia_id?: string
          chunk_id?: string | null
          criado_em?: string
          criado_por?: string | null
          descricao?: string
          documento_id?: string | null
          id?: string
          item?: number
          pagina?: number | null
          resultado?: string
          trecho_literal?: string | null
          valor_autorizado_centavos?: number | null
          votos_contra?: number | null
          votos_favor?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "deliberacoes_assembleia_id_fkey"
            columns: ["assembleia_id"]
            isOneToOne: false
            referencedRelation: "assembleias"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "deliberacoes_chunk_id_fkey"
            columns: ["chunk_id"]
            isOneToOne: false
            referencedRelation: "chunks"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "deliberacoes_criado_por_fkey"
            columns: ["criado_por"]
            isOneToOne: false
            referencedRelation: "pessoas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "deliberacoes_criado_por_fkey"
            columns: ["criado_por"]
            isOneToOne: false
            referencedRelation: "vw_pessoas_mascaradas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "deliberacoes_documento_id_fkey"
            columns: ["documento_id"]
            isOneToOne: false
            referencedRelation: "documentos"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "deliberacoes_documento_id_fkey"
            columns: ["documento_id"]
            isOneToOne: false
            referencedRelation: "vw_documentos_publicados"
            referencedColumns: ["id"]
          },
        ]
      }
      documento_paginas: {
        Row: {
          confianca_ocr: number | null
          criado_em: string
          documento_id: string
          fonte_texto: string
          id: string
          motor_texto: string | null
          pagina: number
          rotacao: number | null
          texto: string | null
          texto_nativo: string | null
          versao_pipeline: number
          visibilidade:
            | Database["public"]["Enums"]["visibilidade_documento"]
            | null
        }
        Insert: {
          confianca_ocr?: number | null
          criado_em?: string
          documento_id: string
          fonte_texto?: string
          id?: string
          motor_texto?: string | null
          pagina: number
          rotacao?: number | null
          texto?: string | null
          texto_nativo?: string | null
          versao_pipeline?: number
          visibilidade?:
            | Database["public"]["Enums"]["visibilidade_documento"]
            | null
        }
        Update: {
          confianca_ocr?: number | null
          criado_em?: string
          documento_id?: string
          fonte_texto?: string
          id?: string
          motor_texto?: string | null
          pagina?: number
          rotacao?: number | null
          texto?: string | null
          texto_nativo?: string | null
          versao_pipeline?: number
          visibilidade?:
            | Database["public"]["Enums"]["visibilidade_documento"]
            | null
        }
        Relationships: [
          {
            foreignKeyName: "documento_paginas_documento_id_fkey"
            columns: ["documento_id"]
            isOneToOne: false
            referencedRelation: "documentos"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "documento_paginas_documento_id_fkey"
            columns: ["documento_id"]
            isOneToOne: false
            referencedRelation: "vw_documentos_publicados"
            referencedColumns: ["id"]
          },
        ]
      }
      documento_unidades: {
        Row: {
          criado_em: string
          documento_id: string
          unidade_id: string
        }
        Insert: {
          criado_em?: string
          documento_id: string
          unidade_id: string
        }
        Update: {
          criado_em?: string
          documento_id?: string
          unidade_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "documento_unidades_documento_id_fkey"
            columns: ["documento_id"]
            isOneToOne: false
            referencedRelation: "documentos"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "documento_unidades_documento_id_fkey"
            columns: ["documento_id"]
            isOneToOne: false
            referencedRelation: "vw_documentos_publicados"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "documento_unidades_unidade_id_fkey"
            columns: ["unidade_id"]
            isOneToOne: false
            referencedRelation: "unidades"
            referencedColumns: ["id"]
          },
        ]
      }
      documentos: {
        Row: {
          atualizado_em: string
          bytes: number | null
          competencia: string | null
          criado_em: string
          criado_por: string | null
          data_documento: string | null
          erro_detalhe: string | null
          id: string
          indexado_em: string | null
          metadados: Json
          ocr_aplicado: boolean
          paginas: number | null
          publicado_em: string | null
          publicado_por: string | null
          sha256: string | null
          status: Database["public"]["Enums"]["status_documento"]
          storage_bucket: string
          storage_path: string
          tem_paginas_mistas: boolean
          tipo: string
          titulo: string
          versao_pipeline: number
          visibilidade: Database["public"]["Enums"]["visibilidade_documento"]
        }
        Insert: {
          atualizado_em?: string
          bytes?: number | null
          competencia?: string | null
          criado_em?: string
          criado_por?: string | null
          data_documento?: string | null
          erro_detalhe?: string | null
          id?: string
          indexado_em?: string | null
          metadados?: Json
          ocr_aplicado?: boolean
          paginas?: number | null
          publicado_em?: string | null
          publicado_por?: string | null
          sha256?: string | null
          status?: Database["public"]["Enums"]["status_documento"]
          storage_bucket?: string
          storage_path: string
          tem_paginas_mistas?: boolean
          tipo: string
          titulo: string
          versao_pipeline?: number
          visibilidade?: Database["public"]["Enums"]["visibilidade_documento"]
        }
        Update: {
          atualizado_em?: string
          bytes?: number | null
          competencia?: string | null
          criado_em?: string
          criado_por?: string | null
          data_documento?: string | null
          erro_detalhe?: string | null
          id?: string
          indexado_em?: string | null
          metadados?: Json
          ocr_aplicado?: boolean
          paginas?: number | null
          publicado_em?: string | null
          publicado_por?: string | null
          sha256?: string | null
          status?: Database["public"]["Enums"]["status_documento"]
          storage_bucket?: string
          storage_path?: string
          tem_paginas_mistas?: boolean
          tipo?: string
          titulo?: string
          versao_pipeline?: number
          visibilidade?: Database["public"]["Enums"]["visibilidade_documento"]
        }
        Relationships: [
          {
            foreignKeyName: "documentos_criado_por_fkey"
            columns: ["criado_por"]
            isOneToOne: false
            referencedRelation: "pessoas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "documentos_criado_por_fkey"
            columns: ["criado_por"]
            isOneToOne: false
            referencedRelation: "vw_pessoas_mascaradas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "documentos_publicado_por_fkey"
            columns: ["publicado_por"]
            isOneToOne: false
            referencedRelation: "pessoas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "documentos_publicado_por_fkey"
            columns: ["publicado_por"]
            isOneToOne: false
            referencedRelation: "vw_pessoas_mascaradas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "documentos_tipo_fkey"
            columns: ["tipo"]
            isOneToOne: false
            referencedRelation: "tipos_documento"
            referencedColumns: ["codigo"]
          },
        ]
      }
      fornecedor_dados_bancarios: {
        Row: {
          agencia: string | null
          banco: string | null
          chave_pix_hash: string | null
          conta_mascarada: string | null
          documento_id: string | null
          fornecedor_id: string
          id: string
          registrado_por: string | null
          vigente_ate: string | null
          vigente_desde: string
        }
        Insert: {
          agencia?: string | null
          banco?: string | null
          chave_pix_hash?: string | null
          conta_mascarada?: string | null
          documento_id?: string | null
          fornecedor_id: string
          id?: string
          registrado_por?: string | null
          vigente_ate?: string | null
          vigente_desde?: string
        }
        Update: {
          agencia?: string | null
          banco?: string | null
          chave_pix_hash?: string | null
          conta_mascarada?: string | null
          documento_id?: string | null
          fornecedor_id?: string
          id?: string
          registrado_por?: string | null
          vigente_ate?: string | null
          vigente_desde?: string
        }
        Relationships: [
          {
            foreignKeyName: "fornecedor_dados_bancarios_documento_id_fkey"
            columns: ["documento_id"]
            isOneToOne: false
            referencedRelation: "documentos"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fornecedor_dados_bancarios_documento_id_fkey"
            columns: ["documento_id"]
            isOneToOne: false
            referencedRelation: "vw_documentos_publicados"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fornecedor_dados_bancarios_fornecedor_id_fkey"
            columns: ["fornecedor_id"]
            isOneToOne: false
            referencedRelation: "fornecedores"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fornecedor_dados_bancarios_registrado_por_fkey"
            columns: ["registrado_por"]
            isOneToOne: false
            referencedRelation: "pessoas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fornecedor_dados_bancarios_registrado_por_fkey"
            columns: ["registrado_por"]
            isOneToOne: false
            referencedRelation: "vw_pessoas_mascaradas"
            referencedColumns: ["id"]
          },
        ]
      }
      fornecedores: {
        Row: {
          ativo: boolean
          categoria: string | null
          cnpj: string | null
          cpf_enc: string | null
          cpf_hash: string | null
          criado_em: string
          criado_por: string | null
          eh_administradora: boolean
          eh_sindico_terceirizado: boolean
          id: string
          nome_fantasia: string | null
          razao_social: string
        }
        Insert: {
          ativo?: boolean
          categoria?: string | null
          cnpj?: string | null
          cpf_enc?: string | null
          cpf_hash?: string | null
          criado_em?: string
          criado_por?: string | null
          eh_administradora?: boolean
          eh_sindico_terceirizado?: boolean
          id?: string
          nome_fantasia?: string | null
          razao_social: string
        }
        Update: {
          ativo?: boolean
          categoria?: string | null
          cnpj?: string | null
          cpf_enc?: string | null
          cpf_hash?: string | null
          criado_em?: string
          criado_por?: string | null
          eh_administradora?: boolean
          eh_sindico_terceirizado?: boolean
          id?: string
          nome_fantasia?: string | null
          razao_social?: string
        }
        Relationships: [
          {
            foreignKeyName: "fornecedores_criado_por_fkey"
            columns: ["criado_por"]
            isOneToOne: false
            referencedRelation: "pessoas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fornecedores_criado_por_fkey"
            columns: ["criado_por"]
            isOneToOne: false
            referencedRelation: "vw_pessoas_mascaradas"
            referencedColumns: ["id"]
          },
        ]
      }
      lancamento_anexos: {
        Row: {
          descricao: string | null
          enviado_em: string
          enviado_por: string
          id: string
          lancamento_id: string
          sha256: string
          storage_bucket: string
          storage_path: string
          tipo: string
        }
        Insert: {
          descricao?: string | null
          enviado_em?: string
          enviado_por: string
          id?: string
          lancamento_id: string
          sha256: string
          storage_bucket?: string
          storage_path: string
          tipo: string
        }
        Update: {
          descricao?: string | null
          enviado_em?: string
          enviado_por?: string
          id?: string
          lancamento_id?: string
          sha256?: string
          storage_bucket?: string
          storage_path?: string
          tipo?: string
        }
        Relationships: [
          {
            foreignKeyName: "lancamento_anexos_enviado_por_fkey"
            columns: ["enviado_por"]
            isOneToOne: false
            referencedRelation: "pessoas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "lancamento_anexos_enviado_por_fkey"
            columns: ["enviado_por"]
            isOneToOne: false
            referencedRelation: "vw_pessoas_mascaradas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "lancamento_anexos_lancamento_id_fkey"
            columns: ["lancamento_id"]
            isOneToOne: false
            referencedRelation: "lancamentos"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "lancamento_anexos_lancamento_id_fkey"
            columns: ["lancamento_id"]
            isOneToOne: false
            referencedRelation: "vw_lancamentos_com_comprovante"
            referencedColumns: ["lancamento_id"]
          },
        ]
      }
      lancamentos: {
        Row: {
          conta_id: string
          criado_em: string
          criado_por: string
          data_caixa: string | null
          data_competencia: string
          deliberacao_id: string | null
          documento_id: string
          estorna_lancamento_id: string | null
          fornecedor_id: string | null
          fundo: Database["public"]["Enums"]["fundo"]
          historico: string
          id: string
          motivo_estorno: string | null
          origem: Database["public"]["Enums"]["origem_lancamento"]
          pagina_origem: number
          tipo: Database["public"]["Enums"]["tipo_lancamento"]
          valor_centavos: number
        }
        Insert: {
          conta_id: string
          criado_em?: string
          criado_por: string
          data_caixa?: string | null
          data_competencia: string
          deliberacao_id?: string | null
          documento_id: string
          estorna_lancamento_id?: string | null
          fornecedor_id?: string | null
          fundo?: Database["public"]["Enums"]["fundo"]
          historico: string
          id?: string
          motivo_estorno?: string | null
          origem?: Database["public"]["Enums"]["origem_lancamento"]
          pagina_origem: number
          tipo: Database["public"]["Enums"]["tipo_lancamento"]
          valor_centavos: number
        }
        Update: {
          conta_id?: string
          criado_em?: string
          criado_por?: string
          data_caixa?: string | null
          data_competencia?: string
          deliberacao_id?: string | null
          documento_id?: string
          estorna_lancamento_id?: string | null
          fornecedor_id?: string | null
          fundo?: Database["public"]["Enums"]["fundo"]
          historico?: string
          id?: string
          motivo_estorno?: string | null
          origem?: Database["public"]["Enums"]["origem_lancamento"]
          pagina_origem?: number
          tipo?: Database["public"]["Enums"]["tipo_lancamento"]
          valor_centavos?: number
        }
        Relationships: [
          {
            foreignKeyName: "lancamentos_conta_id_fkey"
            columns: ["conta_id"]
            isOneToOne: false
            referencedRelation: "contas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "lancamentos_criado_por_fkey"
            columns: ["criado_por"]
            isOneToOne: false
            referencedRelation: "pessoas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "lancamentos_criado_por_fkey"
            columns: ["criado_por"]
            isOneToOne: false
            referencedRelation: "vw_pessoas_mascaradas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "lancamentos_deliberacao_id_fkey"
            columns: ["deliberacao_id"]
            isOneToOne: false
            referencedRelation: "deliberacoes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "lancamentos_documento_id_fkey"
            columns: ["documento_id"]
            isOneToOne: false
            referencedRelation: "documentos"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "lancamentos_documento_id_fkey"
            columns: ["documento_id"]
            isOneToOne: false
            referencedRelation: "vw_documentos_publicados"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "lancamentos_estorna_lancamento_id_fkey"
            columns: ["estorna_lancamento_id"]
            isOneToOne: true
            referencedRelation: "lancamentos"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "lancamentos_estorna_lancamento_id_fkey"
            columns: ["estorna_lancamento_id"]
            isOneToOne: true
            referencedRelation: "vw_lancamentos_com_comprovante"
            referencedColumns: ["lancamento_id"]
          },
          {
            foreignKeyName: "lancamentos_fornecedor_id_fkey"
            columns: ["fornecedor_id"]
            isOneToOne: false
            referencedRelation: "fornecedores"
            referencedColumns: ["id"]
          },
        ]
      }
      orcamento: {
        Row: {
          conta_id: string
          criado_em: string
          criado_por: string | null
          documento_id: string | null
          exercicio: number
          id: string
          mes: number
          valor_previsto_centavos: number
        }
        Insert: {
          conta_id: string
          criado_em?: string
          criado_por?: string | null
          documento_id?: string | null
          exercicio: number
          id?: string
          mes: number
          valor_previsto_centavos: number
        }
        Update: {
          conta_id?: string
          criado_em?: string
          criado_por?: string | null
          documento_id?: string | null
          exercicio?: number
          id?: string
          mes?: number
          valor_previsto_centavos?: number
        }
        Relationships: [
          {
            foreignKeyName: "orcamento_conta_id_fkey"
            columns: ["conta_id"]
            isOneToOne: false
            referencedRelation: "contas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "orcamento_criado_por_fkey"
            columns: ["criado_por"]
            isOneToOne: false
            referencedRelation: "pessoas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "orcamento_criado_por_fkey"
            columns: ["criado_por"]
            isOneToOne: false
            referencedRelation: "vw_pessoas_mascaradas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "orcamento_documento_id_fkey"
            columns: ["documento_id"]
            isOneToOne: false
            referencedRelation: "documentos"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "orcamento_documento_id_fkey"
            columns: ["documento_id"]
            isOneToOne: false
            referencedRelation: "vw_documentos_publicados"
            referencedColumns: ["id"]
          },
        ]
      }
      papeis: {
        Row: {
          concedido_por: string | null
          criado_em: string
          encerrado_por: string | null
          id: string
          mandato_fim: string | null
          mandato_inicio: string
          motivo: string | null
          motivo_fim: Database["public"]["Enums"]["motivo_fim_mandato"] | null
          papel: Database["public"]["Enums"]["papel"]
          pessoa_id: string
        }
        Insert: {
          concedido_por?: string | null
          criado_em?: string
          encerrado_por?: string | null
          id?: string
          mandato_fim?: string | null
          mandato_inicio?: string
          motivo?: string | null
          motivo_fim?: Database["public"]["Enums"]["motivo_fim_mandato"] | null
          papel: Database["public"]["Enums"]["papel"]
          pessoa_id: string
        }
        Update: {
          concedido_por?: string | null
          criado_em?: string
          encerrado_por?: string | null
          id?: string
          mandato_fim?: string | null
          mandato_inicio?: string
          motivo?: string | null
          motivo_fim?: Database["public"]["Enums"]["motivo_fim_mandato"] | null
          papel?: Database["public"]["Enums"]["papel"]
          pessoa_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "papeis_concedido_por_fkey"
            columns: ["concedido_por"]
            isOneToOne: false
            referencedRelation: "pessoas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "papeis_concedido_por_fkey"
            columns: ["concedido_por"]
            isOneToOne: false
            referencedRelation: "vw_pessoas_mascaradas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "papeis_encerrado_por_fkey"
            columns: ["encerrado_por"]
            isOneToOne: false
            referencedRelation: "pessoas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "papeis_encerrado_por_fkey"
            columns: ["encerrado_por"]
            isOneToOne: false
            referencedRelation: "vw_pessoas_mascaradas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "papeis_pessoa_id_fkey"
            columns: ["pessoa_id"]
            isOneToOne: false
            referencedRelation: "pessoas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "papeis_pessoa_id_fkey"
            columns: ["pessoa_id"]
            isOneToOne: false
            referencedRelation: "vw_pessoas_mascaradas"
            referencedColumns: ["id"]
          },
        ]
      }
      parecer_signatarios: {
        Row: {
          assinado_em: string | null
          parecer_id: string
          pessoa_id: string
        }
        Insert: {
          assinado_em?: string | null
          parecer_id: string
          pessoa_id: string
        }
        Update: {
          assinado_em?: string | null
          parecer_id?: string
          pessoa_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "parecer_signatarios_parecer_id_fkey"
            columns: ["parecer_id"]
            isOneToOne: false
            referencedRelation: "pareceres"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "parecer_signatarios_pessoa_id_fkey"
            columns: ["pessoa_id"]
            isOneToOne: false
            referencedRelation: "pessoas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "parecer_signatarios_pessoa_id_fkey"
            columns: ["pessoa_id"]
            isOneToOne: false
            referencedRelation: "vw_pessoas_mascaradas"
            referencedColumns: ["id"]
          },
        ]
      }
      pareceres: {
        Row: {
          competencia_fim: string
          competencia_inicio: string
          conclusao: string | null
          criado_em: string
          documento_id: string | null
          emitido_em: string | null
          id: string
          status: string
          texto: string
          versao: number
        }
        Insert: {
          competencia_fim: string
          competencia_inicio: string
          conclusao?: string | null
          criado_em?: string
          documento_id?: string | null
          emitido_em?: string | null
          id?: string
          status?: string
          texto: string
          versao?: number
        }
        Update: {
          competencia_fim?: string
          competencia_inicio?: string
          conclusao?: string | null
          criado_em?: string
          documento_id?: string | null
          emitido_em?: string | null
          id?: string
          status?: string
          texto?: string
          versao?: number
        }
        Relationships: [
          {
            foreignKeyName: "pareceres_documento_id_fkey"
            columns: ["documento_id"]
            isOneToOne: false
            referencedRelation: "documentos"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "pareceres_documento_id_fkey"
            columns: ["documento_id"]
            isOneToOne: false
            referencedRelation: "vw_documentos_publicados"
            referencedColumns: ["id"]
          },
        ]
      }
      periodos_fechados: {
        Row: {
          competencia: string
          fechado_em: string
          fechado_por: string
          motivo_reabertura: string | null
          reaberto_em: string | null
          reaberto_por: string | null
          saldo_final_centavos: number | null
          saldo_inicial_centavos: number | null
        }
        Insert: {
          competencia: string
          fechado_em?: string
          fechado_por: string
          motivo_reabertura?: string | null
          reaberto_em?: string | null
          reaberto_por?: string | null
          saldo_final_centavos?: number | null
          saldo_inicial_centavos?: number | null
        }
        Update: {
          competencia?: string
          fechado_em?: string
          fechado_por?: string
          motivo_reabertura?: string | null
          reaberto_em?: string | null
          reaberto_por?: string | null
          saldo_final_centavos?: number | null
          saldo_inicial_centavos?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "periodos_fechados_fechado_por_fkey"
            columns: ["fechado_por"]
            isOneToOne: false
            referencedRelation: "pessoas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "periodos_fechados_fechado_por_fkey"
            columns: ["fechado_por"]
            isOneToOne: false
            referencedRelation: "vw_pessoas_mascaradas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "periodos_fechados_reaberto_por_fkey"
            columns: ["reaberto_por"]
            isOneToOne: false
            referencedRelation: "pessoas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "periodos_fechados_reaberto_por_fkey"
            columns: ["reaberto_por"]
            isOneToOne: false
            referencedRelation: "vw_pessoas_mascaradas"
            referencedColumns: ["id"]
          },
        ]
      }
      pessoas: {
        Row: {
          anonimizada_em: string | null
          ativa: boolean
          atualizado_em: string
          auth_user_id: string | null
          cpf_enc: string | null
          cpf_hash: string | null
          cpf_ultimos_digitos: string | null
          criado_em: string
          criado_por: string | null
          email: string | null
          id: string
          nome: string
          observacoes: string | null
          telefone: string | null
        }
        Insert: {
          anonimizada_em?: string | null
          ativa?: boolean
          atualizado_em?: string
          auth_user_id?: string | null
          cpf_enc?: string | null
          cpf_hash?: string | null
          cpf_ultimos_digitos?: string | null
          criado_em?: string
          criado_por?: string | null
          email?: string | null
          id?: string
          nome: string
          observacoes?: string | null
          telefone?: string | null
        }
        Update: {
          anonimizada_em?: string | null
          ativa?: boolean
          atualizado_em?: string
          auth_user_id?: string | null
          cpf_enc?: string | null
          cpf_hash?: string | null
          cpf_ultimos_digitos?: string | null
          criado_em?: string
          criado_por?: string | null
          email?: string | null
          id?: string
          nome?: string
          observacoes?: string | null
          telefone?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "pessoas_criado_por_fkey"
            columns: ["criado_por"]
            isOneToOne: false
            referencedRelation: "pessoas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "pessoas_criado_por_fkey"
            columns: ["criado_por"]
            isOneToOne: false
            referencedRelation: "vw_pessoas_mascaradas"
            referencedColumns: ["id"]
          },
        ]
      }
      questionamentos: {
        Row: {
          autor_id: string
          criado_em: string
          id: string
          lancamento_id: string
          respondido_em: string | null
          respondido_por: string | null
          resposta: string | null
          status: Database["public"]["Enums"]["status_questionamento"]
          texto: string
        }
        Insert: {
          autor_id: string
          criado_em?: string
          id?: string
          lancamento_id: string
          respondido_em?: string | null
          respondido_por?: string | null
          resposta?: string | null
          status?: Database["public"]["Enums"]["status_questionamento"]
          texto: string
        }
        Update: {
          autor_id?: string
          criado_em?: string
          id?: string
          lancamento_id?: string
          respondido_em?: string | null
          respondido_por?: string | null
          resposta?: string | null
          status?: Database["public"]["Enums"]["status_questionamento"]
          texto?: string
        }
        Relationships: [
          {
            foreignKeyName: "questionamentos_autor_id_fkey"
            columns: ["autor_id"]
            isOneToOne: false
            referencedRelation: "pessoas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "questionamentos_autor_id_fkey"
            columns: ["autor_id"]
            isOneToOne: false
            referencedRelation: "vw_pessoas_mascaradas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "questionamentos_lancamento_id_fkey"
            columns: ["lancamento_id"]
            isOneToOne: false
            referencedRelation: "lancamentos"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "questionamentos_lancamento_id_fkey"
            columns: ["lancamento_id"]
            isOneToOne: false
            referencedRelation: "vw_lancamentos_com_comprovante"
            referencedColumns: ["lancamento_id"]
          },
          {
            foreignKeyName: "questionamentos_respondido_por_fkey"
            columns: ["respondido_por"]
            isOneToOne: false
            referencedRelation: "pessoas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "questionamentos_respondido_por_fkey"
            columns: ["respondido_por"]
            isOneToOne: false
            referencedRelation: "vw_pessoas_mascaradas"
            referencedColumns: ["id"]
          },
        ]
      }
      sinonimos: {
        Row: {
          ativo: boolean
          criado_em: string
          expansoes: string[]
          id: string
          termo: string
          termo_normalizado: string | null
        }
        Insert: {
          ativo?: boolean
          criado_em?: string
          expansoes: string[]
          id?: string
          termo: string
          termo_normalizado?: string | null
        }
        Update: {
          ativo?: boolean
          criado_em?: string
          expansoes?: string[]
          id?: string
          termo?: string
          termo_normalizado?: string | null
        }
        Relationships: []
      }
      tipos_alerta: {
        Row: {
          ativo: boolean
          codigo: string
          descricao_regra: string
          nome: string
          requer_historico_meses: number
          severidade_padrao: Database["public"]["Enums"]["severidade_alerta"]
        }
        Insert: {
          ativo?: boolean
          codigo: string
          descricao_regra: string
          nome: string
          requer_historico_meses?: number
          severidade_padrao: Database["public"]["Enums"]["severidade_alerta"]
        }
        Update: {
          ativo?: boolean
          codigo?: string
          descricao_regra?: string
          nome?: string
          requer_historico_meses?: number
          severidade_padrao?: Database["public"]["Enums"]["severidade_alerta"]
        }
        Relationships: []
      }
      tipos_documento: {
        Row: {
          ativo: boolean
          codigo: string
          nome: string
          ordem: number
          permite_publico: boolean
          retencao_meses: number | null
          visibilidade_padrao: Database["public"]["Enums"]["visibilidade_documento"]
        }
        Insert: {
          ativo?: boolean
          codigo: string
          nome: string
          ordem?: number
          permite_publico?: boolean
          retencao_meses?: number | null
          visibilidade_padrao?: Database["public"]["Enums"]["visibilidade_documento"]
        }
        Update: {
          ativo?: boolean
          codigo?: string
          nome?: string
          ordem?: number
          permite_publico?: boolean
          retencao_meses?: number | null
          visibilidade_padrao?: Database["public"]["Enums"]["visibilidade_documento"]
        }
        Relationships: []
      }
      unidades: {
        Row: {
          area_m2: number | null
          ativa: boolean
          atualizado_em: string
          bloco: string
          criado_em: string
          fracao_ideal: number
          id: string
          numero: string
          ordem: number | null
        }
        Insert: {
          area_m2?: number | null
          ativa?: boolean
          atualizado_em?: string
          bloco?: string
          criado_em?: string
          fracao_ideal: number
          id?: string
          numero: string
          ordem?: number | null
        }
        Update: {
          area_m2?: number | null
          ativa?: boolean
          atualizado_em?: string
          bloco?: string
          criado_em?: string
          fracao_ideal?: number
          id?: string
          numero?: string
          ordem?: number | null
        }
        Relationships: []
      }
      vinculos: {
        Row: {
          criado_em: string
          criado_por: string | null
          fim: string | null
          id: string
          inicio: string
          motivo_fim: Database["public"]["Enums"]["motivo_fim_vinculo"] | null
          pessoa_id: string
          tipo: Database["public"]["Enums"]["tipo_vinculo"]
          unidade_id: string
        }
        Insert: {
          criado_em?: string
          criado_por?: string | null
          fim?: string | null
          id?: string
          inicio?: string
          motivo_fim?: Database["public"]["Enums"]["motivo_fim_vinculo"] | null
          pessoa_id: string
          tipo: Database["public"]["Enums"]["tipo_vinculo"]
          unidade_id: string
        }
        Update: {
          criado_em?: string
          criado_por?: string | null
          fim?: string | null
          id?: string
          inicio?: string
          motivo_fim?: Database["public"]["Enums"]["motivo_fim_vinculo"] | null
          pessoa_id?: string
          tipo?: Database["public"]["Enums"]["tipo_vinculo"]
          unidade_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "vinculos_criado_por_fkey"
            columns: ["criado_por"]
            isOneToOne: false
            referencedRelation: "pessoas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "vinculos_criado_por_fkey"
            columns: ["criado_por"]
            isOneToOne: false
            referencedRelation: "vw_pessoas_mascaradas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "vinculos_pessoa_id_fkey"
            columns: ["pessoa_id"]
            isOneToOne: false
            referencedRelation: "pessoas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "vinculos_pessoa_id_fkey"
            columns: ["pessoa_id"]
            isOneToOne: false
            referencedRelation: "vw_pessoas_mascaradas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "vinculos_unidade_id_fkey"
            columns: ["unidade_id"]
            isOneToOne: false
            referencedRelation: "unidades"
            referencedColumns: ["id"]
          },
        ]
      }
    }
    Views: {
      vw_documentos_publicados: {
        Row: {
          competencia: string | null
          data_documento: string | null
          id: string | null
          paginas: number | null
          publicado_em: string | null
          tipo: string | null
          titulo: string | null
          visibilidade:
            | Database["public"]["Enums"]["visibilidade_documento"]
            | null
        }
        Insert: {
          competencia?: string | null
          data_documento?: string | null
          id?: string | null
          paginas?: number | null
          publicado_em?: string | null
          tipo?: string | null
          titulo?: string | null
          visibilidade?:
            | Database["public"]["Enums"]["visibilidade_documento"]
            | null
        }
        Update: {
          competencia?: string | null
          data_documento?: string | null
          id?: string | null
          paginas?: number | null
          publicado_em?: string | null
          tipo?: string | null
          titulo?: string | null
          visibilidade?:
            | Database["public"]["Enums"]["visibilidade_documento"]
            | null
        }
        Relationships: [
          {
            foreignKeyName: "documentos_tipo_fkey"
            columns: ["tipo"]
            isOneToOne: false
            referencedRelation: "tipos_documento"
            referencedColumns: ["codigo"]
          },
        ]
      }
      vw_inadimplencia_agregada: {
        Row: {
          competencia: string | null
          em_atraso_centavos: number | null
          pct: number | null
          qtd_unidades_em_atraso: number | null
          total_centavos: number | null
        }
        Relationships: []
      }
      vw_inadimplencia_nominal: {
        Row: {
          bloco: string | null
          competencia: string | null
          numero: string | null
          pessoa_id: string | null
          pessoa_nome: string | null
          status: Database["public"]["Enums"]["status_cobranca"] | null
          unidade_id: string | null
          valor_centavos: number | null
          valor_pago_centavos: number | null
          vencimento: string | null
        }
        Relationships: [
          {
            foreignKeyName: "cobrancas_unidade_id_fkey"
            columns: ["unidade_id"]
            isOneToOne: false
            referencedRelation: "unidades"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "vinculos_pessoa_id_fkey"
            columns: ["pessoa_id"]
            isOneToOne: false
            referencedRelation: "pessoas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "vinculos_pessoa_id_fkey"
            columns: ["pessoa_id"]
            isOneToOne: false
            referencedRelation: "vw_pessoas_mascaradas"
            referencedColumns: ["id"]
          },
        ]
      }
      vw_lancamentos_com_comprovante: {
        Row: {
          conta_id: string | null
          data_competencia: string | null
          lancamento_id: string | null
          tem_comprovante: boolean | null
          total_anexos: number | null
          total_cotacoes: number | null
          valor_centavos: number | null
        }
        Relationships: [
          {
            foreignKeyName: "lancamentos_conta_id_fkey"
            columns: ["conta_id"]
            isOneToOne: false
            referencedRelation: "contas"
            referencedColumns: ["id"]
          },
        ]
      }
      vw_orcado_realizado: {
        Row: {
          conta_id: string | null
          exercicio: number | null
          mes: number | null
          previsto_centavos: number | null
          realizado_centavos: number | null
          variacao_centavos: number | null
          variacao_pct: number | null
        }
        Relationships: [
          {
            foreignKeyName: "orcamento_conta_id_fkey"
            columns: ["conta_id"]
            isOneToOne: false
            referencedRelation: "contas"
            referencedColumns: ["id"]
          },
        ]
      }
      vw_pessoas_mascaradas: {
        Row: {
          cpf_mascarado: string | null
          email: string | null
          id: string | null
          nome: string | null
        }
        Insert: {
          cpf_mascarado?: never
          email?: string | null
          id?: string | null
          nome?: string | null
        }
        Update: {
          cpf_mascarado?: never
          email?: string | null
          id?: string | null
          nome?: string | null
        }
        Relationships: []
      }
      vw_realizado_por_conta: {
        Row: {
          competencia: string | null
          conta_codigo: string | null
          conta_id: string | null
          conta_nome: string | null
          realizado_centavos: number | null
        }
        Relationships: [
          {
            foreignKeyName: "lancamentos_conta_id_fkey"
            columns: ["conta_id"]
            isOneToOne: false
            referencedRelation: "contas"
            referencedColumns: ["id"]
          },
        ]
      }
    }
    Functions: {
      buscar_lexica: {
        Args: { p_consulta: string; p_limite?: number }
        Returns: {
          chunk_id: string
          documento_id: string
          pagina_fim: number
          pagina_ini: number
          rank: number
          secao: string
          texto: string
          tipo: string
          titulo: string
          trecho: string
        }[]
      }
      eh_editor_vigente_linha: {
        Args: {
          p_mandato_fim: string
          p_mandato_inicio: string
          p_papel: Database["public"]["Enums"]["papel"]
          p_pessoa_ativa: boolean
        }
        Returns: boolean
      }
      unaccent_imutavel: { Args: { txt: string }; Returns: string }
      websearch_to_tsquery_pt: {
        Args: { p_consulta: string }
        Returns: unknown
      }
    }
    Enums: {
      fundo: "nenhum" | "reserva" | "obras"
      motivo_fim_mandato:
        | "renuncia"
        | "substituicao"
        | "termino_de_mandato"
        | "erro_cadastral"
        | "conta_comprometida"
      motivo_fim_vinculo:
        | "venda"
        | "fim_locacao"
        | "obito"
        | "pedido_titular"
        | "erro_cadastral"
      natureza_conta: "receita" | "despesa"
      origem_lancamento: "balancete_importado" | "manual" | "ajuste"
      papel: "editor" | "conselho" | "morador"
      severidade_alerta: "baixa" | "media" | "alta" | "critica"
      status_alerta: "aberto" | "em_analise" | "resolvido" | "ignorado"
      status_cobranca: "aberta" | "paga" | "atrasada" | "acordo" | "cancelada"
      status_documento:
        | "pendente"
        | "processando"
        | "indexado"
        | "em_revisao"
        | "publicado"
        | "erro"
      status_job: "pendente" | "processando" | "concluido" | "erro" | "morto"
      status_questionamento: "aberto" | "respondido" | "resolvido"
      tipo_assembleia: "ago" | "age" | "agi" | "conselho_fiscal"
      tipo_lancamento: "receita" | "despesa"
      tipo_vinculo: "proprietario" | "inquilino" | "residente" | "procurador"
      visibilidade_documento:
        | "publico"
        | "autenticado"
        | "conselho"
        | "restrito"
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
}

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] &
        DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] &
        DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R
      }
      ? R
      : never
    : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I
      }
      ? I
      : never
    : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U
      }
      ? U
      : never
    : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never = never,
> = DefaultSchemaEnumNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
    : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  graphql_public: {
    Enums: {},
  },
  public: {
    Enums: {
      fundo: ["nenhum", "reserva", "obras"],
      motivo_fim_mandato: [
        "renuncia",
        "substituicao",
        "termino_de_mandato",
        "erro_cadastral",
        "conta_comprometida",
      ],
      motivo_fim_vinculo: [
        "venda",
        "fim_locacao",
        "obito",
        "pedido_titular",
        "erro_cadastral",
      ],
      natureza_conta: ["receita", "despesa"],
      origem_lancamento: ["balancete_importado", "manual", "ajuste"],
      papel: ["editor", "conselho", "morador"],
      severidade_alerta: ["baixa", "media", "alta", "critica"],
      status_alerta: ["aberto", "em_analise", "resolvido", "ignorado"],
      status_cobranca: ["aberta", "paga", "atrasada", "acordo", "cancelada"],
      status_documento: [
        "pendente",
        "processando",
        "indexado",
        "em_revisao",
        "publicado",
        "erro",
      ],
      status_job: ["pendente", "processando", "concluido", "erro", "morto"],
      status_questionamento: ["aberto", "respondido", "resolvido"],
      tipo_assembleia: ["ago", "age", "agi", "conselho_fiscal"],
      tipo_lancamento: ["receita", "despesa"],
      tipo_vinculo: ["proprietario", "inquilino", "residente", "procurador"],
      visibilidade_documento: [
        "publico",
        "autenticado",
        "conselho",
        "restrito",
      ],
    },
  },
} as const

