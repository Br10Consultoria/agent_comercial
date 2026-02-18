-- ============================================================================
-- QUERIES DE PRÁTICA - DO BÁSICO AO AVANÇADO
-- ============================================================================
-- Execute no PostgreSQL após o deploy para praticar e validar os dados
-- Pode executar via: docker exec -e PGPASSWORD=SUA_SENHA CONTAINER \
--   psql -U postgres -d agente_comercial -f /caminho/04_queries_pratica.sql
-- ============================================================================

-- NÍVEL 1: Consultas Básicas
SELECT * FROM provedores;
SELECT nome_provedor, plano FROM provedores;
SELECT COUNT(*) FROM leads;
SELECT * FROM leads LIMIT 5;
SELECT nome, whatsapp FROM leads ORDER BY nome;

-- NÍVEL 2: Filtros
SELECT * FROM provedores WHERE nome_provedor = 'FibraNet MG';
SELECT nome_plano, velocidade, valor FROM planos WHERE valor < 100;
SELECT nome, endereco_instalacao FROM leads WHERE endereco_instalacao LIKE '%Belo Horizonte%';
SELECT mensagem, created_at FROM mensagens WHERE is_bot = true;
SELECT nome_provedor, ativo FROM provedores WHERE ativo = true;

-- NÍVEL 3: Condições Múltiplas
SELECT nome_plano, valor FROM planos WHERE valor >= 100 AND valor <= 200;
SELECT nome, tags FROM leads WHERE 'lead_quente' = ANY(tags) OR 'lead_morno' = ANY(tags);
SELECT nome_provedor, plano FROM provedores WHERE plano != 'basico';
SELECT nome_plano, valor FROM planos WHERE ativo = true AND valor < 150;

-- NÍVEL 4: Agregações
SELECT COUNT(*) as total_leads FROM leads WHERE provedor_id = 1;
SELECT AVG(valor) as preco_medio FROM planos;
SELECT MAX(valor) as plano_mais_caro FROM planos;
SELECT MIN(valor) as plano_mais_barato FROM planos;
SELECT is_bot, COUNT(*) as quantidade FROM mensagens GROUP BY is_bot;

-- NÍVEL 5: Agrupamentos
SELECT provedor_id, COUNT(*) as total_leads FROM leads GROUP BY provedor_id;
SELECT provedor_id, COUNT(*) as total_planos FROM planos GROUP BY provedor_id;
SELECT provedor_id, AVG(valor) as preco_medio FROM planos GROUP BY provedor_id;
SELECT lead_id, COUNT(*) as total_mensagens FROM mensagens GROUP BY lead_id;
SELECT provedor_id, COUNT(*) as total_leads FROM leads GROUP BY provedor_id HAVING COUNT(*) > 2;

-- NÍVEL 6: Consultas Elaboradas
SELECT nome_plano, velocidade, valor FROM planos ORDER BY valor DESC;
SELECT nome, whatsapp, created_at FROM leads ORDER BY created_at DESC LIMIT 3;
SELECT unnest(tags) as tag, COUNT(*) as frequencia FROM leads GROUP BY tag ORDER BY frequencia DESC;
SELECT mensagem, is_bot, created_at FROM mensagens WHERE lead_id = 1 ORDER BY created_at;
SELECT 
  (SELECT COUNT(*) FROM provedores) as total_provedores,
  (SELECT COUNT(*) FROM leads) as total_leads,
  (SELECT COUNT(*) FROM planos) as total_planos,
  (SELECT COUNT(*) FROM mensagens) as total_mensagens;

-- NÍVEL 7: JSONB
SELECT nome_provedor, config_bot->>'modelo' as modelo_ia FROM provedores;
SELECT nome_provedor, config_bot->>'modelo' as modelo, config_bot->>'max_tokens' as tokens, config_bot->>'temperatura' as temp FROM provedores;
SELECT nome_provedor FROM provedores WHERE config_bot->>'modelo' = 'gpt-4.1-mini-2025-04-14';
SELECT nome_provedor FROM provedores WHERE config_bot ? 'prompt_sdr';
SELECT nome_provedor FROM provedores WHERE config_bot->>'prompt_sdr' ILIKE '%COT%';
SELECT nome_provedor, plano, config_bot->>'modelo' as modelo_ia, (config_bot->>'max_tokens')::integer as tokens, (config_bot->>'temperatura')::decimal as temperatura, LENGTH(config_bot->>'prompt_sdr') as tamanho_prompt FROM provedores ORDER BY tamanho_prompt DESC;

-- NÍVEL 8: Views
SELECT * FROM vw_leads_completo;
SELECT * FROM vw_planos_completo;
SELECT * FROM vw_conversas LIMIT 20;
SELECT * FROM vw_resumo_provedores;

-- NÍVEL 9: Funções
SELECT * FROM buscar_lead_por_whatsapp('553199887766@s.whatsapp.net');
SELECT * FROM buscar_config_bot('fibranet_mg_whatsapp');
SELECT * FROM historico_conversa(1);
SELECT * FROM listar_planos_provedor(1);
SELECT * FROM dashboard_resumo();
SELECT * FROM dashboard_resumo(1);
