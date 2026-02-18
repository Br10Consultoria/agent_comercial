-- ============================================================================
-- CONSULTA DE CREDENCIAIS GERADAS
-- ============================================================================
-- Execute este script APÓS o 01_setup_completo.sql para visualizar
-- todas as apikeys e credenciais geradas automaticamente
-- ============================================================================

-- Todas as credenciais
SELECT 
  provedor_nome,
  instancia,
  apikey_gerada,
  senha_banco,
  notas,
  created_at
FROM credenciais_geradas
ORDER BY id;

-- Resumo do sistema
SELECT * FROM dashboard_resumo();

-- Verificação rápida de todas as tabelas
SELECT 
  'provedores' as tabela, COUNT(*) as registros FROM provedores
UNION ALL
SELECT 'planos', COUNT(*) FROM planos
UNION ALL
SELECT 'leads', COUNT(*) FROM leads
UNION ALL
SELECT 'mensagens', COUNT(*) FROM mensagens
UNION ALL
SELECT 'credenciais_geradas', COUNT(*) FROM credenciais_geradas
ORDER BY tabela;
