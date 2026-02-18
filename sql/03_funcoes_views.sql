-- ============================================================================
-- AGENTE COMERCIAL ISP - Funções e Views
-- ============================================================================
-- Funções utilitárias para integração com N8N, Chatwoot e aplicações
-- Executado automaticamente pelo deploy-database.sh
-- ============================================================================

BEGIN;

-- ============================================================================
-- FUNÇÕES
-- ============================================================================

-- Buscar lead por número WhatsApp (usado pelo N8N ao receber mensagem)
CREATE OR REPLACE FUNCTION buscar_lead_por_whatsapp(p_remotejid text)
RETURNS TABLE(
  lead_id integer,
  lead_nome text,
  lead_whatsapp text,
  lead_cpf_cnpj text,
  lead_endereco text,
  lead_tags text[],
  provedor text,
  provedor_id integer,
  instancia text
) AS $$
BEGIN
  RETURN QUERY
  SELECT l.id, l.nome, l.whatsapp, l.cpf_cnpj, l.endereco_instalacao, l.tags,
         p.nome_provedor, p.id, p.instancia
  FROM leads l
  JOIN provedores p ON p.id = l.provedor_id
  WHERE l.remotejid = p_remotejid;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Buscar config do bot por instância (usado pelo N8N para obter prompt)
CREATE OR REPLACE FUNCTION buscar_config_bot(p_instancia text)
RETURNS TABLE(
  provedor_id integer,
  nome_provedor text,
  config jsonb,
  apikey text
) AS $$
BEGIN
  RETURN QUERY
  SELECT p.id, p.nome_provedor, p.config_bot, p.apikey
  FROM provedores p
  WHERE p.instancia = p_instancia AND p.ativo = true;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Registrar nova mensagem (usado pelo N8N após cada mensagem)
CREATE OR REPLACE FUNCTION registrar_mensagem(
  p_lead_id integer,
  p_mensagem text,
  p_is_bot boolean DEFAULT false
)
RETURNS integer AS $$
DECLARE
  v_msg_id integer;
BEGIN
  INSERT INTO mensagens (mensagem, is_bot, lead_id)
  VALUES (p_mensagem, p_is_bot, p_lead_id)
  RETURNING id INTO v_msg_id;
  
  UPDATE leads SET updated_at = now() WHERE id = p_lead_id;
  
  RETURN v_msg_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Obter histórico de conversa (usado pelo N8N para contexto da IA)
CREATE OR REPLACE FUNCTION historico_conversa(p_lead_id integer, p_limite integer DEFAULT 50)
RETURNS TABLE(
  msg_id integer,
  mensagem text,
  remetente text,
  enviada_em timestamp
) AS $$
BEGIN
  RETURN QUERY
  SELECT 
    m.id,
    m.mensagem,
    CASE WHEN m.is_bot THEN 'assistant' ELSE 'user' END,
    m.created_at
  FROM mensagens m
  WHERE m.lead_id = p_lead_id
  ORDER BY m.created_at ASC
  LIMIT p_limite;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Criar ou atualizar lead (upsert - usado pelo N8N ao receber novo contato)
CREATE OR REPLACE FUNCTION upsert_lead(
  p_remotejid text,
  p_provedor_id integer,
  p_nome text DEFAULT NULL,
  p_cpf_cnpj text DEFAULT NULL,
  p_endereco text DEFAULT NULL,
  p_whatsapp text DEFAULT NULL,
  p_tags text[] DEFAULT NULL
)
RETURNS integer AS $$
DECLARE
  v_lead_id integer;
BEGIN
  SELECT id INTO v_lead_id FROM leads 
  WHERE remotejid = p_remotejid AND provedor_id = p_provedor_id;
  
  IF v_lead_id IS NOT NULL THEN
    UPDATE leads SET
      nome = COALESCE(p_nome, nome),
      cpf_cnpj = COALESCE(p_cpf_cnpj, cpf_cnpj),
      endereco_instalacao = COALESCE(p_endereco, endereco_instalacao),
      whatsapp = COALESCE(p_whatsapp, whatsapp),
      tags = COALESCE(p_tags, tags),
      updated_at = now()
    WHERE id = v_lead_id;
  ELSE
    INSERT INTO leads (nome, cpf_cnpj, endereco_instalacao, remotejid, whatsapp, tags, provedor_id)
    VALUES (p_nome, p_cpf_cnpj, p_endereco, p_remotejid, p_whatsapp, COALESCE(p_tags, ARRAY['novo_lead']), p_provedor_id)
    RETURNING id INTO v_lead_id;
  END IF;
  
  RETURN v_lead_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Listar planos de um provedor (usado pelo agente IA para apresentar planos)
CREATE OR REPLACE FUNCTION listar_planos_provedor(p_provedor_id integer)
RETURNS TABLE(
  plano_id integer,
  nome text,
  velocidade text,
  valor decimal,
  ativo boolean
) AS $$
BEGIN
  RETURN QUERY
  SELECT pl.id, pl.nome_plano, pl.velocidade, pl.valor, pl.ativo
  FROM planos pl
  WHERE pl.provedor_id = p_provedor_id AND pl.ativo = true
  ORDER BY pl.valor ASC;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Atualizar tags do lead (usado pelo N8N para qualificação)
CREATE OR REPLACE FUNCTION atualizar_tags_lead(
  p_lead_id integer,
  p_tags text[]
)
RETURNS void AS $$
BEGIN
  UPDATE leads SET tags = p_tags, updated_at = now()
  WHERE id = p_lead_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Dashboard resumo (usado por painéis administrativos)
CREATE OR REPLACE FUNCTION dashboard_resumo(p_provedor_id integer DEFAULT NULL)
RETURNS TABLE(
  total_leads bigint,
  leads_quentes bigint,
  leads_mornos bigint,
  leads_frios bigint,
  total_mensagens bigint,
  mensagens_bot bigint,
  mensagens_humanas bigint,
  total_planos bigint,
  plano_mais_barato decimal,
  plano_mais_caro decimal
) AS $$
BEGIN
  RETURN QUERY
  SELECT
    (SELECT COUNT(*) FROM leads WHERE (p_provedor_id IS NULL OR leads.provedor_id = p_provedor_id)),
    (SELECT COUNT(*) FROM leads WHERE 'lead_quente' = ANY(tags) AND (p_provedor_id IS NULL OR leads.provedor_id = p_provedor_id)),
    (SELECT COUNT(*) FROM leads WHERE 'lead_morno' = ANY(tags) AND (p_provedor_id IS NULL OR leads.provedor_id = p_provedor_id)),
    (SELECT COUNT(*) FROM leads WHERE 'lead_frio' = ANY(tags) AND (p_provedor_id IS NULL OR leads.provedor_id = p_provedor_id)),
    (SELECT COUNT(*) FROM mensagens m JOIN leads l ON l.id = m.lead_id WHERE (p_provedor_id IS NULL OR l.provedor_id = p_provedor_id)),
    (SELECT COUNT(*) FROM mensagens m JOIN leads l ON l.id = m.lead_id WHERE m.is_bot = true AND (p_provedor_id IS NULL OR l.provedor_id = p_provedor_id)),
    (SELECT COUNT(*) FROM mensagens m JOIN leads l ON l.id = m.lead_id WHERE m.is_bot = false AND (p_provedor_id IS NULL OR l.provedor_id = p_provedor_id)),
    (SELECT COUNT(*) FROM planos WHERE (p_provedor_id IS NULL OR planos.provedor_id = p_provedor_id)),
    (SELECT MIN(valor) FROM planos WHERE ativo = true AND (p_provedor_id IS NULL OR planos.provedor_id = p_provedor_id)),
    (SELECT MAX(valor) FROM planos WHERE ativo = true AND (p_provedor_id IS NULL OR planos.provedor_id = p_provedor_id));
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- VIEWS
-- ============================================================================

-- Leads com informações completas do provedor
CREATE OR REPLACE VIEW vw_leads_completo AS
SELECT 
  l.id as lead_id,
  l.nome as lead_nome,
  l.whatsapp,
  l.remotejid,
  l.cpf_cnpj,
  l.endereco_instalacao,
  l.tags,
  l.created_at as lead_desde,
  l.updated_at as ultima_atualizacao,
  p.id as provedor_id,
  p.nome_provedor,
  p.instancia,
  (SELECT COUNT(*) FROM mensagens m WHERE m.lead_id = l.id) as total_mensagens,
  (SELECT m.created_at FROM mensagens m WHERE m.lead_id = l.id ORDER BY m.created_at DESC LIMIT 1) as ultima_mensagem
FROM leads l
JOIN provedores p ON p.id = l.provedor_id;

-- Planos com nome do provedor
CREATE OR REPLACE VIEW vw_planos_completo AS
SELECT 
  pl.id as plano_id,
  pl.nome_plano,
  pl.velocidade,
  pl.valor,
  pl.ativo,
  p.id as provedor_id,
  p.nome_provedor,
  p.plano as plano_assinatura
FROM planos pl
JOIN provedores p ON p.id = pl.provedor_id
ORDER BY p.nome_provedor, pl.valor;

-- Conversas formatadas (útil para debug e auditoria)
CREATE OR REPLACE VIEW vw_conversas AS
SELECT 
  m.id as msg_id,
  l.id as lead_id,
  l.nome as lead_nome,
  l.whatsapp,
  p.nome_provedor,
  p.instancia,
  m.mensagem,
  CASE WHEN m.is_bot THEN 'AGENTE_IA' ELSE 'LEAD' END as remetente,
  m.created_at as enviada_em
FROM mensagens m
JOIN leads l ON l.id = m.lead_id
JOIN provedores p ON p.id = l.provedor_id
ORDER BY m.created_at DESC;

-- Resumo por provedor (útil para dashboards)
CREATE OR REPLACE VIEW vw_resumo_provedores AS
SELECT 
  p.id as provedor_id,
  p.nome_provedor,
  p.plano as plano_assinatura,
  p.ativo,
  p.instancia,
  (SELECT COUNT(*) FROM leads l WHERE l.provedor_id = p.id) as total_leads,
  (SELECT COUNT(*) FROM leads l WHERE l.provedor_id = p.id AND 'lead_quente' = ANY(l.tags)) as leads_quentes,
  (SELECT COUNT(*) FROM planos pl WHERE pl.provedor_id = p.id AND pl.ativo = true) as total_planos,
  (SELECT MIN(pl.valor) FROM planos pl WHERE pl.provedor_id = p.id AND pl.ativo = true) as plano_mais_barato,
  (SELECT MAX(pl.valor) FROM planos pl WHERE pl.provedor_id = p.id AND pl.ativo = true) as plano_mais_caro,
  p.config_bot->>'modelo' as modelo_ia,
  p.config_bot->>'webhook_n8n' as webhook_n8n
FROM provedores p
ORDER BY p.id;

COMMIT;
