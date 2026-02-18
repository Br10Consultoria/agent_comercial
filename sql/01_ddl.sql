-- ============================================================================
-- AGENTE COMERCIAL ISP - DDL (Data Definition Language)
-- ============================================================================
-- Tabelas, índices, foreign keys e triggers
-- Executado automaticamente pelo deploy-database.sh
-- ============================================================================

BEGIN;

-- ============================================================================
-- LIMPEZA (idempotente)
-- ============================================================================
DROP TABLE IF EXISTS credenciais_geradas CASCADE;
DROP TABLE IF EXISTS mensagens CASCADE;
DROP TABLE IF EXISTS leads CASCADE;
DROP TABLE IF EXISTS planos CASCADE;
DROP TABLE IF EXISTS provedores CASCADE;

-- ============================================================================
-- TABELAS
-- ============================================================================

-- 1. Provedores/instâncias WhatsApp (tabela pai)
CREATE TABLE provedores(
  id serial NOT NULL,
  nome_provedor text NOT NULL,
  instancia text NOT NULL,
  apikey text NOT NULL,
  config_bot jsonb,
  plano text NOT NULL DEFAULT 'basico',
  ativo boolean NOT NULL DEFAULT true,
  created_at timestamp NOT NULL DEFAULT now(),
  updated_at timestamp NOT NULL DEFAULT now(),
  CONSTRAINT provedores_pkey PRIMARY KEY(id)
);

COMMENT ON TABLE provedores IS 'Provedores de internet com configuração de instância WhatsApp e agente IA';
COMMENT ON COLUMN provedores.instancia IS 'Identificador da instância WhatsApp (Evolution API / Chatwoot)';
COMMENT ON COLUMN provedores.apikey IS 'Chave de API gerada automaticamente para autenticação';
COMMENT ON COLUMN provedores.config_bot IS 'Configurações do agente IA em formato JSONB (modelo, prompt, temperatura, etc)';

-- 2. Planos de internet dos provedores
CREATE TABLE planos(
  id serial NOT NULL,
  nome_plano text NOT NULL,
  velocidade text NOT NULL,
  valor decimal(10,2) NOT NULL,
  provedor_id integer NOT NULL,
  ativo boolean NOT NULL DEFAULT true,
  created_at timestamp NOT NULL DEFAULT now(),
  updated_at timestamp NOT NULL DEFAULT now(),
  CONSTRAINT planos_pkey PRIMARY KEY(id)
);

COMMENT ON TABLE planos IS 'Planos de internet oferecidos por cada provedor';

-- 3. Leads/prospects capturados via WhatsApp
CREATE TABLE leads(
  id serial NOT NULL,
  nome text,
  cpf_cnpj text,
  endereco_instalacao text,
  remotejid text NOT NULL,
  whatsapp text,
  tags text[],
  created_at timestamp NOT NULL DEFAULT now(),
  updated_at timestamp NOT NULL DEFAULT now(),
  provedor_id integer NOT NULL,
  CONSTRAINT leads_pkey PRIMARY KEY(id)
);

COMMENT ON TABLE leads IS 'Leads capturados via WhatsApp pelo agente IA';
COMMENT ON COLUMN leads.remotejid IS 'JID remoto do WhatsApp (identificador único do contato)';
COMMENT ON COLUMN leads.tags IS 'Array de tags para classificação (lead_quente, lead_morno, lead_frio)';

-- 4. Histórico de mensagens da automação
CREATE TABLE mensagens(
  id serial NOT NULL,
  mensagem text NOT NULL,
  is_bot boolean NOT NULL DEFAULT false,
  created_at timestamp NOT NULL DEFAULT now(),
  lead_id integer NOT NULL,
  CONSTRAINT mensagens_pkey PRIMARY KEY(id)
);

COMMENT ON TABLE mensagens IS 'Histórico completo de mensagens entre leads e agente IA';

-- ============================================================================
-- ÍNDICES
-- ============================================================================
CREATE INDEX provedores_instancia_idx ON provedores(instancia);
CREATE INDEX provedores_ativo_idx ON provedores(ativo);
CREATE INDEX planos_provedor_id_idx ON planos(provedor_id);
CREATE INDEX planos_ativo_idx ON planos(ativo);
CREATE INDEX leads_provedor_id_idx ON leads(provedor_id);
CREATE INDEX leads_remotejid_idx ON leads(remotejid);
CREATE INDEX leads_tags_idx ON leads USING GIN(tags);
CREATE INDEX leads_created_at_idx ON leads(created_at DESC);
CREATE INDEX mensagens_lead_id_idx ON mensagens(lead_id);
CREATE INDEX mensagens_created_at_idx ON mensagens(created_at DESC);
CREATE INDEX mensagens_is_bot_idx ON mensagens(is_bot);

-- ============================================================================
-- FOREIGN KEYS
-- ============================================================================
ALTER TABLE planos
  ADD CONSTRAINT planos_provedor_id_fkey
    FOREIGN KEY (provedor_id) REFERENCES provedores (id) ON DELETE CASCADE;

ALTER TABLE leads
  ADD CONSTRAINT leads_provedor_id_fkey
    FOREIGN KEY (provedor_id) REFERENCES provedores (id) ON DELETE CASCADE;

ALTER TABLE mensagens
  ADD CONSTRAINT mensagens_lead_id_fkey
    FOREIGN KEY (lead_id) REFERENCES leads (id) ON DELETE CASCADE;

-- ============================================================================
-- TRIGGER: updated_at automático
-- ============================================================================
CREATE OR REPLACE FUNCTION trigger_set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER set_updated_at_provedores
  BEFORE UPDATE ON provedores
  FOR EACH ROW EXECUTE FUNCTION trigger_set_updated_at();

CREATE TRIGGER set_updated_at_planos
  BEFORE UPDATE ON planos
  FOR EACH ROW EXECUTE FUNCTION trigger_set_updated_at();

CREATE TRIGGER set_updated_at_leads
  BEFORE UPDATE ON leads
  FOR EACH ROW EXECUTE FUNCTION trigger_set_updated_at();

COMMIT;
