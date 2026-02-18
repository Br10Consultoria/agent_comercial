-- ============================================================================
-- QUERIES DE PRÁTICA - DO BÁSICO AO AVANÇADO
-- ============================================================================
-- Execute estas queries após o setup para praticar e validar os dados
-- ============================================================================

-- ============================================================================
-- NÍVEL 1: Consultas Básicas
-- ============================================================================

-- 1. Ver todos os dados de uma tabela
SELECT * FROM provedores;

-- 2. Ver dados específicos
SELECT nome_provedor, plano FROM provedores;

-- 3. Contar registros
SELECT COUNT(*) FROM leads;

-- 4. Ver os primeiros 5 registros
SELECT * FROM leads LIMIT 5;

-- 5. Ordenar dados
SELECT nome, whatsapp FROM leads ORDER BY nome;

-- ============================================================================
-- NÍVEL 2: Usando Filtros
-- ============================================================================

-- 6. Buscar um provedor específico
SELECT * FROM provedores WHERE nome_provedor = 'FibraNet MG';

-- 7. Buscar planos baratos (menos de R$ 100)
SELECT nome_plano, velocidade, valor FROM planos WHERE valor < 100;

-- 8. Buscar leads de Belo Horizonte
SELECT nome, endereco_instalacao FROM leads WHERE endereco_instalacao LIKE '%Belo Horizonte%';

-- 9. Buscar mensagens enviadas pelo agente IA
SELECT mensagem, created_at FROM mensagens WHERE is_bot = true;

-- 10. Buscar provedores ativos
SELECT nome_provedor, ativo FROM provedores WHERE ativo = true;

-- ============================================================================
-- NÍVEL 3: Condições Múltiplas
-- ============================================================================

-- 11. Planos entre R$ 100 e R$ 200
SELECT nome_plano, valor FROM planos WHERE valor >= 100 AND valor <= 200;

-- 12. Leads quentes OU mornos (usando tags)
SELECT nome, tags FROM leads WHERE 'lead_quente' = ANY(tags) OR 'lead_morno' = ANY(tags);

-- 13. Provedores que NÃO são básicos
SELECT nome_provedor, plano FROM provedores WHERE plano != 'basico';

-- 14. Mensagens recentes (últimas 3 horas)
SELECT mensagem, created_at FROM mensagens WHERE created_at >= now() - interval '3 hours';

-- 15. Planos ativos e baratos
SELECT nome_plano, valor FROM planos WHERE ativo = true AND valor < 150;

-- ============================================================================
-- NÍVEL 4: Funções e Agregações
-- ============================================================================

-- 16. Contar leads por provedor
SELECT COUNT(*) as total_leads FROM leads WHERE provedor_id = 1;

-- 17. Valor médio dos planos
SELECT AVG(valor) as preco_medio FROM planos;

-- 18. Plano mais caro
SELECT MAX(valor) as plano_mais_caro FROM planos;

-- 19. Plano mais barato
SELECT MIN(valor) as plano_mais_barato FROM planos;

-- 20. Total de mensagens por tipo
SELECT is_bot, COUNT(*) as quantidade FROM mensagens GROUP BY is_bot;

-- ============================================================================
-- NÍVEL 5: Agrupamentos
-- ============================================================================

-- 21. Contar leads por provedor
SELECT provedor_id, COUNT(*) as total_leads FROM leads GROUP BY provedor_id;

-- 22. Contar planos por provedor
SELECT provedor_id, COUNT(*) as total_planos FROM planos GROUP BY provedor_id;

-- 23. Média de preço por provedor
SELECT provedor_id, AVG(valor) as preco_medio FROM planos GROUP BY provedor_id;

-- 24. Contar mensagens por lead
SELECT lead_id, COUNT(*) as total_mensagens FROM mensagens GROUP BY lead_id;

-- 25. Provedores com mais de 2 leads
SELECT provedor_id, COUNT(*) as total_leads 
FROM leads 
GROUP BY provedor_id 
HAVING COUNT(*) > 2;

-- ============================================================================
-- NÍVEL 6: Consultas Elaboradas
-- ============================================================================

-- 26. Ranking de planos por preço
SELECT nome_plano, velocidade, valor 
FROM planos 
ORDER BY valor DESC;

-- 27. Leads mais recentes
SELECT nome, whatsapp, created_at 
FROM leads 
ORDER BY created_at DESC 
LIMIT 3;

-- 28. Análise de tags populares
SELECT unnest(tags) as tag, COUNT(*) as frequencia 
FROM leads 
GROUP BY tag 
ORDER BY frequencia DESC;

-- 29. Histórico de mensagens de um lead específico
SELECT mensagem, is_bot, created_at 
FROM mensagens 
WHERE lead_id = 1 
ORDER BY created_at;

-- 30. Resumo geral do sistema
SELECT 
    (SELECT COUNT(*) FROM provedores) as total_provedores,
    (SELECT COUNT(*) FROM leads) as total_leads,
    (SELECT COUNT(*) FROM planos) as total_planos,
    (SELECT COUNT(*) FROM mensagens) as total_mensagens;

-- ============================================================================
-- NÍVEL 7: Consultando Campos JSONB
-- ============================================================================

-- 31. Ver configurações dos agentes IA
SELECT nome_provedor, config_bot FROM provedores;

-- 32. Extrair modelo de IA usado
SELECT nome_provedor, config_bot->>'modelo' as modelo_ia FROM provedores;

-- 33. Extrair múltiplos campos do JSON
SELECT 
    nome_provedor,
    config_bot->>'modelo' as modelo,
    config_bot->>'max_tokens' as tokens,
    config_bot->>'temperatura' as temp
FROM provedores;

-- 34. Filtrar por modelo específico
SELECT nome_provedor FROM provedores 
WHERE config_bot->>'modelo' = 'gpt-4.1-mini-2025-04-14';

-- 35. Verificar se tem prompt SDR configurado
SELECT nome_provedor FROM provedores 
WHERE config_bot ? 'prompt_sdr';

-- 36. Buscar palavra no prompt
SELECT nome_provedor FROM provedores 
WHERE config_bot->>'prompt_sdr' ILIKE '%COT%';

-- 37. Relatório completo das configurações de IA
SELECT 
    nome_provedor,
    plano,
    config_bot->>'modelo' as modelo_ia,
    (config_bot->>'max_tokens')::integer as tokens,
    (config_bot->>'temperatura')::decimal as temperatura,
    LENGTH(config_bot->>'prompt_sdr') as tamanho_prompt
FROM provedores
ORDER BY tamanho_prompt DESC;

-- ============================================================================
-- NÍVEL 8: Usando as Views criadas (BÔNUS)
-- ============================================================================

-- 38. Leads completos com info do provedor
SELECT * FROM vw_leads_completo;

-- 39. Planos com nome do provedor
SELECT * FROM vw_planos_completo;

-- 40. Últimas conversas
SELECT * FROM vw_conversas LIMIT 20;

-- ============================================================================
-- NÍVEL 9: Usando as Funções criadas (BÔNUS)
-- ============================================================================

-- 41. Buscar lead por WhatsApp
SELECT * FROM buscar_lead_por_whatsapp('553199887766@s.whatsapp.net');

-- 42. Ver histórico de conversa do lead 1
SELECT * FROM historico_conversa(1);

-- 43. Dashboard geral
SELECT * FROM dashboard_resumo();

-- 44. Dashboard de um provedor específico
SELECT * FROM dashboard_resumo(1);
