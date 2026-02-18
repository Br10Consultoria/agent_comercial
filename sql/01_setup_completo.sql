-- ============================================================================
-- AGENTE COMERCIAL ISP - SCRIPT COMPLETO DE SETUP
-- ============================================================================
-- Descrição: Script profissional para criação e população do banco de dados
--            do sistema de Agente Comercial ISP com automação WhatsApp + IA
-- Compatível com: Supabase (PostgreSQL 15+)
-- Autor: Br10 Consultoria
-- Data: 2025-02-18
-- Versão: 1.0.0
-- ============================================================================
-- 
-- INSTRUÇÕES DE USO:
-- 1. Acesse o Supabase SQL Editor
-- 2. Cole este script inteiro e execute
-- 3. Após execução, consulte a tabela 'credenciais_geradas' para obter
--    as apikeys e senhas geradas automaticamente
-- 4. Use essas credenciais no Chatwoot, N8N e demais integrações
--
-- ============================================================================

-- ============================================================================
-- PARTE 0: EXTENSÕES NECESSÁRIAS
-- ============================================================================
-- pgcrypto já vem habilitada no Supabase, mas garantimos aqui
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ============================================================================
-- PARTE 1: LIMPEZA (DROP) - Remove tudo se já existir (idempotente)
-- ============================================================================
DROP TABLE IF EXISTS credenciais_geradas CASCADE;
DROP TABLE IF EXISTS mensagens CASCADE;
DROP TABLE IF EXISTS leads CASCADE;
DROP TABLE IF EXISTS planos CASCADE;
DROP TABLE IF EXISTS provedores CASCADE;

-- ============================================================================
-- PARTE 2: CRIAÇÃO DAS TABELAS (DDL)
-- ============================================================================

-- 2.1 Tabela de configuração dos provedores/instâncias WhatsApp (tabela pai)
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
COMMENT ON COLUMN provedores.plano IS 'Plano de assinatura do provedor: basico, profissional, enterprise';

-- 2.2 Tabela de planos de internet dos provedores
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
COMMENT ON COLUMN planos.velocidade IS 'Velocidade do plano (ex: 100 Mbps, 500 Mbps)';
COMMENT ON COLUMN planos.valor IS 'Valor mensal do plano em reais (BRL)';

-- 2.3 Tabela principal de leads/prospects capturados via WhatsApp
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
COMMENT ON COLUMN leads.tags IS 'Array de tags para classificação (lead_quente, lead_morno, lead_frio, etc)';

-- 2.4 Tabela de histórico completo de mensagens da automação
CREATE TABLE mensagens(
  id serial NOT NULL,
  mensagem text NOT NULL,
  is_bot boolean NOT NULL DEFAULT false,
  created_at timestamp NOT NULL DEFAULT now(),
  lead_id integer NOT NULL,
  CONSTRAINT mensagens_pkey PRIMARY KEY(id)
);

COMMENT ON TABLE mensagens IS 'Histórico completo de mensagens entre leads e agente IA';
COMMENT ON COLUMN mensagens.is_bot IS 'true = mensagem enviada pelo agente IA, false = mensagem do lead';

-- 2.5 Tabela auxiliar para armazenar credenciais geradas (consulta posterior)
CREATE TABLE credenciais_geradas(
  id serial NOT NULL,
  provedor_nome text NOT NULL,
  instancia text NOT NULL,
  apikey_gerada text NOT NULL,
  senha_banco text NOT NULL,
  url_supabase text DEFAULT 'Preencher após deploy',
  anon_key text DEFAULT 'Preencher após deploy',
  service_role_key text DEFAULT 'Preencher após deploy',
  notas text,
  created_at timestamp NOT NULL DEFAULT now(),
  CONSTRAINT credenciais_geradas_pkey PRIMARY KEY(id)
);

COMMENT ON TABLE credenciais_geradas IS 'Tabela de referência com todas as credenciais geradas - CONSULTE AQUI APÓS EXECUÇÃO';

-- ============================================================================
-- PARTE 3: ÍNDICES PARA OTIMIZAÇÃO
-- ============================================================================
CREATE INDEX provedores_instancia_idx ON provedores(instancia NULLS LAST);
CREATE INDEX provedores_ativo_idx ON provedores(ativo);
CREATE INDEX planos_provedor_id_idx ON planos(provedor_id NULLS LAST);
CREATE INDEX planos_ativo_idx ON planos(ativo);
CREATE INDEX leads_provedor_id_idx ON leads(provedor_id NULLS LAST);
CREATE INDEX leads_remotejid_idx ON leads(remotejid);
CREATE INDEX leads_tags_idx ON leads USING GIN(tags);
CREATE INDEX leads_created_at_idx ON leads(created_at DESC);
CREATE INDEX mensagens_lead_id_idx ON mensagens(lead_id NULLS LAST);
CREATE INDEX mensagens_created_at_idx ON mensagens(created_at DESC);
CREATE INDEX mensagens_is_bot_idx ON mensagens(is_bot);

-- ============================================================================
-- PARTE 4: RELACIONAMENTOS (FOREIGN KEYS)
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
-- PARTE 5: TRIGGER DE UPDATED_AT AUTOMÁTICO
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

-- ============================================================================
-- PARTE 6: POPULAÇÃO DOS DADOS
-- ============================================================================

-- 6.1 Provedores com apikeys geradas automaticamente e config_bot JSONB
INSERT INTO provedores (nome_provedor, instancia, apikey, config_bot, plano, ativo) VALUES

-- Provedor 1: FibraNet MG (Belo Horizonte)
(
  'FibraNet MG',
  'fibranet_mg_whatsapp',
  encode(gen_random_bytes(32), 'hex'),
  '{
    "modelo": "gpt-4.1-mini-2025-04-14",
    "max_tokens": 500,
    "temperatura": 0.7,
    "prompt_sdr": "Você é um agente comercial especializado da FibraNet MG, provedor de internet fibra óptica em Belo Horizonte e região metropolitana. Use a técnica COT (Chain of Thought) para qualificar leads. Primeiro, identifique a necessidade do cliente. Segundo, apresente o plano mais adequado. Terceiro, colete os dados para agendamento da instalação. Seja cordial, objetivo e use linguagem mineira quando apropriado. Sempre pergunte o endereço completo para verificar cobertura. Dados que você DEVE coletar: nome completo, CPF, endereço de instalação, melhor horário para instalação.",
    "prompt_boas_vindas": "Olá! 👋 Sou o assistente virtual da FibraNet MG! Temos os melhores planos de fibra óptica de BH. Como posso te ajudar hoje?",
    "horario_atendimento": {"inicio": "08:00", "fim": "22:00"},
    "webhook_n8n": "https://n8n.fibranetmg.com.br/webhook/whatsapp",
    "chatwoot_inbox_id": 1
  }'::jsonb,
  'profissional',
  true
),

-- Provedor 2: VeloCity Net (São Paulo)
(
  'VeloCity Net',
  'velocity_sp_whatsapp',
  encode(gen_random_bytes(32), 'hex'),
  '{
    "modelo": "gpt-4.1-mini-2025-04-14",
    "max_tokens": 600,
    "temperatura": 0.6,
    "prompt_sdr": "Você é o agente comercial inteligente da VeloCity Net, provedor de internet de alta velocidade em São Paulo capital e Grande SP. Utilize raciocínio COT para conduzir a conversa. Etapa 1: Cumprimente e identifique se é cliente novo ou existente. Etapa 2: Entenda a necessidade (residencial ou empresarial). Etapa 3: Apresente planos compatíveis com a região. Etapa 4: Colete dados cadastrais. Seja profissional mas descontraído. Sempre verifique viabilidade técnica pelo CEP antes de fechar.",
    "prompt_boas_vindas": "E aí! 🚀 Bem-vindo à VeloCity Net! Internet ultra rápida pra SP inteira. Bora encontrar o plano perfeito pra você?",
    "horario_atendimento": {"inicio": "07:00", "fim": "23:00"},
    "webhook_n8n": "https://n8n.velocitynet.com.br/webhook/whatsapp",
    "chatwoot_inbox_id": 2
  }'::jsonb,
  'enterprise',
  true
),

-- Provedor 3: ConectaBR Telecom (Rio de Janeiro)
(
  'ConectaBR Telecom',
  'conectabr_rj_whatsapp',
  encode(gen_random_bytes(32), 'hex'),
  '{
    "modelo": "gpt-4.1-mini-2025-04-14",
    "max_tokens": 500,
    "temperatura": 0.7,
    "prompt_sdr": "Você é o assistente comercial da ConectaBR Telecom, provedor de internet no Rio de Janeiro e Niterói. Siga o método COT: 1) Identifique o perfil do cliente (residencial/comercial). 2) Verifique a região de cobertura. 3) Sugira o melhor plano. 4) Agende a instalação. Seja simpático e use referências cariocas quando possível. Importante: sempre informe sobre a promoção de fidelidade de 12 meses com desconto.",
    "prompt_boas_vindas": "Fala, carioca! 🏖️ Aqui é da ConectaBR Telecom! Internet fibra óptica no RJ inteiro. Como posso te ajudar?",
    "horario_atendimento": {"inicio": "08:00", "fim": "21:00"},
    "webhook_n8n": "https://n8n.conectabr.com.br/webhook/whatsapp",
    "chatwoot_inbox_id": 3
  }'::jsonb,
  'basico',
  true
),

-- Provedor 4: TurboLink RS (Porto Alegre)
(
  'TurboLink RS',
  'turbolink_rs_whatsapp',
  encode(gen_random_bytes(32), 'hex'),
  '{
    "modelo": "gpt-4.1-mini-2025-04-14",
    "max_tokens": 450,
    "temperatura": 0.65,
    "prompt_sdr": "Você é o agente virtual da TurboLink RS, provedor de internet fibra óptica em Porto Alegre e região metropolitana gaúcha. Use COT para qualificação: Passo 1 - Saudação e identificação da demanda. Passo 2 - Verificação de cobertura pelo bairro/CEP. Passo 3 - Apresentação dos planos disponíveis. Passo 4 - Coleta de dados e agendamento. Seja cordial e use expressões gaúchas quando natural. Destaque o suporte técnico 24h como diferencial.",
    "prompt_boas_vindas": "Bah, tchê! 🧉 Bem-vindo à TurboLink RS! A melhor internet fibra do Sul. Em que posso te ajudar, parceiro?",
    "horario_atendimento": {"inicio": "08:00", "fim": "22:00"},
    "webhook_n8n": "https://n8n.turbolinkrs.com.br/webhook/whatsapp",
    "chatwoot_inbox_id": 4
  }'::jsonb,
  'profissional',
  true
),

-- Provedor 5: NordesteFibra (Recife)
(
  'NordesteFibra',
  'nordestefibra_pe_whatsapp',
  encode(gen_random_bytes(32), 'hex'),
  '{
    "modelo": "gpt-4.1-mini-2025-04-14",
    "max_tokens": 500,
    "temperatura": 0.7,
    "prompt_sdr": "Você é o agente comercial da NordesteFibra, provedor de internet em Recife e Região Metropolitana. Aplique COT: 1) Identifique se o lead veio por indicação ou campanha. 2) Entenda o uso (streaming, home office, gaming). 3) Recomende o plano ideal. 4) Colete dados e agende visita técnica. Seja acolhedor e use linguagem nordestina quando adequado. Sempre mencione o programa de indicação com desconto.",
    "prompt_boas_vindas": "Oi, tudo bem? 🌴 Aqui é da NordesteFibra! A internet mais arretada de Recife! Como posso te ajudar?",
    "horario_atendimento": {"inicio": "07:30", "fim": "21:30"},
    "webhook_n8n": "https://n8n.nordestefibra.com.br/webhook/whatsapp",
    "chatwoot_inbox_id": 5
  }'::jsonb,
  'basico',
  true
);

-- 6.2 Planos de Internet (5 planos por provedor = 25 planos)
INSERT INTO planos (nome_plano, velocidade, valor, provedor_id, ativo) VALUES
-- FibraNet MG (provedor_id = 1)
('Fibra Start',      '100 Mbps',  79.90,  1, true),
('Fibra Plus',       '200 Mbps',  99.90,  1, true),
('Fibra Turbo',      '400 Mbps',  129.90, 1, true),
('Fibra Ultra',      '600 Mbps',  169.90, 1, true),
('Fibra Giga',       '1 Gbps',    219.90, 1, true),

-- VeloCity Net (provedor_id = 2)
('Speed 200',        '200 Mbps',  89.90,  2, true),
('Speed 400',        '400 Mbps',  119.90, 2, true),
('Speed 600',        '600 Mbps',  149.90, 2, true),
('Speed Giga',       '1 Gbps',    199.90, 2, true),
('Speed Giga Pro',   '2 Gbps',    349.90, 2, true),

-- ConectaBR Telecom (provedor_id = 3)
('Conecta 100',      '100 Mbps',  69.90,  3, true),
('Conecta 300',      '300 Mbps',  99.90,  3, true),
('Conecta 500',      '500 Mbps',  139.90, 3, true),
('Conecta Giga',     '1 Gbps',    189.90, 3, true),
('Conecta Empresa',  '1 Gbps',    299.90, 3, true),

-- TurboLink RS (provedor_id = 4)
('Turbo 150',        '150 Mbps',  74.90,  4, true),
('Turbo 300',        '300 Mbps',  104.90, 4, true),
('Turbo 500',        '500 Mbps',  144.90, 4, true),
('Turbo Giga',       '1 Gbps',    199.90, 4, true),
('Turbo Business',   '1 Gbps',    279.90, 4, true),

-- NordesteFibra (provedor_id = 5)
('Nordeste 100',     '100 Mbps',  59.90,  5, true),
('Nordeste 200',     '200 Mbps',  79.90,  5, true),
('Nordeste 400',     '400 Mbps',  109.90, 5, true),
('Nordeste 600',     '600 Mbps',  149.90, 5, true),
('Nordeste Giga',    '1 Gbps',    199.90, 5, true);

-- 6.3 Leads capturados via WhatsApp (20 leads distribuídos entre provedores)
INSERT INTO leads (nome, cpf_cnpj, endereco_instalacao, remotejid, whatsapp, tags, provedor_id) VALUES
-- Leads FibraNet MG (provedor_id = 1)
('Carlos Eduardo Silva',    '123.456.789-00', 'Rua dos Inconfidentes, 450, Savassi, Belo Horizonte - MG',           '553199887766@s.whatsapp.net', '(31) 99988-7766', ARRAY['lead_quente', 'residencial', 'fibra_giga'],       1),
('Ana Paula Oliveira',      '234.567.890-11', 'Av. Afonso Pena, 1200, Centro, Belo Horizonte - MG',                 '553198776655@s.whatsapp.net', '(31) 98877-6655', ARRAY['lead_morno', 'residencial'],                      1),
('Roberto Mendes Ltda',     '12.345.678/0001-90', 'Rua Espírito Santo, 800, Centro, Belo Horizonte - MG',           '553197665544@s.whatsapp.net', '(31) 97766-5544', ARRAY['lead_quente', 'empresarial', 'fibra_giga'],       1),
('Fernanda Costa Santos',   '345.678.901-22', 'Rua Rio de Janeiro, 1500, Lourdes, Belo Horizonte - MG',             '553196554433@s.whatsapp.net', '(31) 96655-4433', ARRAY['lead_frio', 'residencial'],                       1),

-- Leads VeloCity Net (provedor_id = 2)
('João Pedro Nakamura',     '456.789.012-33', 'Av. Paulista, 1578, Bela Vista, São Paulo - SP',                     '5511987654321@s.whatsapp.net', '(11) 98765-4321', ARRAY['lead_quente', 'empresarial', 'speed_giga'],      2),
('Maria Luísa Ferreira',    '567.890.123-44', 'Rua Augusta, 2300, Consolação, São Paulo - SP',                      '5511976543210@s.whatsapp.net', '(11) 97654-3210', ARRAY['lead_morno', 'residencial', 'streaming'],        2),
('Tech Solutions SP Ltda',  '23.456.789/0001-01', 'Av. Faria Lima, 3000, Pinheiros, São Paulo - SP',                '5511965432109@s.whatsapp.net', '(11) 96543-2109', ARRAY['lead_quente', 'empresarial', 'link_dedicado'],   2),
('Lucas Gabriel Souza',     '678.901.234-55', 'Rua Oscar Freire, 900, Jardins, São Paulo - SP',                     '5511954321098@s.whatsapp.net', '(11) 95432-1098', ARRAY['lead_morno', 'residencial', 'gaming'],           2),

-- Leads ConectaBR Telecom (provedor_id = 3)
('Rafaela Almeida',         '789.012.345-66', 'Av. Atlântica, 2500, Copacabana, Rio de Janeiro - RJ',               '5521998877665@s.whatsapp.net', '(21) 99887-7665', ARRAY['lead_quente', 'residencial'],                    3),
('Pedro Henrique Lima',     '890.123.456-77', 'Rua Visconde de Pirajá, 300, Ipanema, Rio de Janeiro - RJ',          '5521987766554@s.whatsapp.net', '(21) 98776-6554', ARRAY['lead_frio', 'residencial'],                      3),
('Escritório Carioca Adv',  '34.567.890/0001-12', 'Av. Rio Branco, 156, Centro, Rio de Janeiro - RJ',               '5521976655443@s.whatsapp.net', '(21) 97665-5443', ARRAY['lead_quente', 'empresarial'],                    3),
('Camila Rodrigues',        '901.234.567-88', 'Rua das Laranjeiras, 450, Laranjeiras, Rio de Janeiro - RJ',         '5521965544332@s.whatsapp.net', '(21) 96554-4332', ARRAY['lead_morno', 'residencial', 'home_office'],      3),

-- Leads TurboLink RS (provedor_id = 4)
('Marcos Vinícius Becker',  '012.345.678-99', 'Rua dos Andradas, 1200, Centro Histórico, Porto Alegre - RS',        '5551998877665@s.whatsapp.net', '(51) 99887-7665', ARRAY['lead_quente', 'residencial', 'turbo_giga'],      4),
('Juliana Schneider',       '111.222.333-44', 'Av. Ipiranga, 6681, Partenon, Porto Alegre - RS',                    '5551987766554@s.whatsapp.net', '(51) 98776-6554', ARRAY['lead_morno', 'residencial'],                     4),
('Gaúcha Tech ME',          '45.678.901/0001-23', 'Rua Voluntários da Pátria, 800, Centro, Porto Alegre - RS',      '5551976655443@s.whatsapp.net', '(51) 97665-5443', ARRAY['lead_quente', 'empresarial', 'turbo_business'],  4),
('Ricardo Azevedo',         '222.333.444-55', 'Av. Protásio Alves, 3000, Petrópolis, Porto Alegre - RS',            '5551965544332@s.whatsapp.net', '(51) 96554-4332', ARRAY['lead_frio', 'residencial'],                      4),

-- Leads NordesteFibra (provedor_id = 5)
('Thiago Barbosa',          '333.444.555-66', 'Av. Boa Viagem, 4500, Boa Viagem, Recife - PE',                      '5581998877665@s.whatsapp.net', '(81) 99887-7665', ARRAY['lead_quente', 'residencial', 'nordeste_giga'],   5),
('Patrícia Cavalcanti',     '444.555.666-77', 'Rua do Bom Jesus, 200, Recife Antigo, Recife - PE',                  '5581987766554@s.whatsapp.net', '(81) 98776-6554', ARRAY['lead_morno', 'residencial'],                     5),
('Recife Digital Ltda',     '56.789.012/0001-34', 'Av. Agamenon Magalhães, 1500, Derby, Recife - PE',               '5581976655443@s.whatsapp.net', '(81) 97665-5443', ARRAY['lead_quente', 'empresarial'],                    5),
('Amanda Freitas',          '555.666.777-88', 'Rua da Aurora, 350, Boa Vista, Recife - PE',                          '5581965544332@s.whatsapp.net', '(81) 96554-4332', ARRAY['lead_frio', 'residencial', 'indicacao'],         5);

-- 6.4 Mensagens de conversas (simulação realista de atendimento via WhatsApp)

-- Conversa 1: Carlos Eduardo (Lead 1 - FibraNet MG - Lead Quente)
INSERT INTO mensagens (mensagem, is_bot, lead_id, created_at) VALUES
('Oi, boa tarde! Vi o anúncio de vocês no Instagram. Quero saber sobre os planos de internet.', false, 1, now() - interval '2 hours'),
('Olá, Carlos! 👋 Que bom que nos encontrou! Sou o assistente virtual da FibraNet MG. Temos planos de fibra óptica de 100 Mbps até 1 Gbps. Pra eu te indicar o melhor plano, me conta: o uso seria residencial ou empresarial?', true, 1, now() - interval '2 hours' + interval '30 seconds'),
('Residencial mesmo. Somos em 4 pessoas em casa, todo mundo usa streaming e eu faço home office.', false, 1, now() - interval '1 hour 55 minutes'),
('Perfeito! Com 4 pessoas usando streaming e home office, recomendo nosso plano **Fibra Ultra 600 Mbps** por R$ 169,90/mês ou o **Fibra Giga 1 Gbps** por R$ 219,90/mês. Ambos garantem estabilidade pra todo mundo. Qual te interessa mais?', true, 1, now() - interval '1 hour 54 minutes'),
('O Fibra Giga parece bom. Qual o prazo de instalação?', false, 1, now() - interval '1 hour 50 minutes'),
('Ótima escolha! 🚀 O Fibra Giga tem instalação em até 48h úteis. Pra verificar a cobertura e agendar, preciso do seu endereço completo. Pode me informar?', true, 1, now() - interval '1 hour 49 minutes'),
('Rua dos Inconfidentes, 450, Savassi, BH', false, 1, now() - interval '1 hour 45 minutes'),
('Excelente! A Savassi tem cobertura total da nossa fibra! ✅ Pra finalizar o cadastro, preciso do seu nome completo e CPF. Pode me passar?', true, 1, now() - interval '1 hour 44 minutes'),
('Carlos Eduardo Silva, CPF 123.456.789-00', false, 1, now() - interval '1 hour 40 minutes'),
('Perfeito, Carlos! Cadastro realizado com sucesso! 🎉 Vou encaminhar para nossa equipe técnica agendar a instalação. Você prefere manhã ou tarde?', true, 1, now() - interval '1 hour 39 minutes'),

-- Conversa 2: João Pedro (Lead 5 - VeloCity Net - Lead Quente Empresarial)
('Preciso de internet empresarial pra meu escritório na Paulista. Vocês atendem?', false, 5, now() - interval '3 hours'),
('Olá! 🚀 Claro que atendemos! A Av. Paulista é uma das nossas áreas com melhor cobertura. Sou o assistente da VeloCity Net. Pra empresas, temos planos a partir de 200 Mbps com IP fixo. Quantos colaboradores usam a internet no escritório?', true, 5, now() - interval '3 hours' + interval '25 seconds'),
('Somos uns 15 funcionários. Precisamos de algo bem estável, usamos sistemas em nuvem e videoconferência o dia todo.', false, 5, now() - interval '2 hours 55 minutes'),
('Com 15 colaboradores usando nuvem e vídeo, recomendo nosso **Speed Giga Pro 2 Gbps** por R$ 349,90/mês. Inclui IP fixo, SLA de 99,5% e suporte prioritário. Quer que eu detalhe?', true, 5, now() - interval '2 hours 54 minutes'),
('Sim, me manda os detalhes. E qual o CNPJ de vocês pra eu verificar?', false, 5, now() - interval '2 hours 50 minutes'),
('Nosso CNPJ é 12.345.678/0001-99. O Speed Giga Pro inclui: ✅ 2 Gbps simétricos, ✅ IP fixo dedicado, ✅ SLA 99,5% com multa, ✅ Suporte 24/7 prioritário, ✅ Instalação em até 5 dias úteis. Posso agendar uma visita técnica?', true, 5, now() - interval '2 hours 49 minutes'),

-- Conversa 3: Rafaela Almeida (Lead 9 - ConectaBR - Lead Quente)
('Boa noite! Acabei de me mudar pra Copacabana e preciso de internet urgente!', false, 9, now() - interval '5 hours'),
('Boa noite, bem-vinda a Copacabana! 🏖️ Sou da ConectaBR Telecom. Temos cobertura total em Copa! Pra uso residencial, nossos planos vão de 100 Mbps a 1 Gbps. O que você mais usa? Streaming, home office, games?', true, 9, now() - interval '5 hours' + interval '20 seconds'),
('Uso bastante Netflix e trabalho de casa 3x por semana. Quero algo bom mas sem pagar muito caro.', false, 9, now() - interval '4 hours 55 minutes'),
('Entendi perfeitamente! Pra Netflix + home office, o **Conecta 300 por R$ 99,90/mês** é ideal! E temos uma promoção: na fidelidade de 12 meses, sai por R$ 89,90/mês. 🎉 Quer aproveitar?', true, 9, now() - interval '4 hours 54 minutes'),
('Esse preço tá ótimo! Quero sim! Como faço?', false, 9, now() - interval '4 hours 50 minutes'),
('Maravilha! 🎉 Me passa seu nome completo, CPF e o endereço exato com número do apartamento que já inicio seu cadastro!', true, 9, now() - interval '4 hours 49 minutes'),

-- Conversa 4: Marcos Vinícius (Lead 13 - TurboLink RS - Lead Quente)
('Buenas! Tô querendo trocar de provedor. A internet aqui tá muito ruim.', false, 13, now() - interval '4 hours'),
('Bah, tchê! 🧉 Entendo a frustração! Sou o assistente da TurboLink RS. Vamos resolver isso! Me conta: qual velocidade você tem hoje e o que precisa?', true, 13, now() - interval '4 hours' + interval '30 seconds'),
('Tenho 100 mega mas não chega nem na metade. Preciso de algo que funcione de verdade.', false, 13, now() - interval '3 hours 55 minutes'),
('Tri ruim isso! 😤 Na TurboLink usamos fibra óptica FTTH, que entrega velocidade real. Recomendo o **Turbo 300 por R$ 104,90/mês** - é o mais pedido! E nosso diferencial: suporte técnico 24h com atendimento humano. Quer testar?', true, 13, now() - interval '3 hours 54 minutes'),
('Suporte 24h é bom demais. Mas vocês cobram instalação?', false, 13, now() - interval '3 hours 50 minutes'),
('Instalação é GRÁTIS! 🎉 E o roteador Wi-Fi 6 já tá incluso em comodato. Sem surpresas na fatura! Me passa teu endereço que verifico a cobertura na hora.', true, 13, now() - interval '3 hours 49 minutes'),

-- Conversa 5: Thiago Barbosa (Lead 17 - NordesteFibra - Lead Quente)
('Eae, vi que vocês tem internet fibra em Boa Viagem. Quanto tá o plano mais rápido?', false, 17, now() - interval '6 hours'),
('Oi! 🌴 Que bom que perguntou! Nosso plano top é o **Nordeste Giga 1 Gbps por R$ 199,90/mês**! É o mais arretado de Recife! Você mora em Boa Viagem mesmo?', true, 17, now() - interval '6 hours' + interval '25 seconds'),
('Moro sim, na Av. Boa Viagem, 4500. Mas achei caro. Tem algo mais em conta?', false, 17, now() - interval '5 hours 55 minutes'),
('Claro! Temos o **Nordeste 400 por R$ 109,90/mês** que é excelente! E olha: se você indicar um amigo, ganha R$ 20 de desconto por 6 meses! 🤝 Pra que você mais usa a internet?', true, 17, now() - interval '5 hours 54 minutes'),
('Uso pra streaming, jogo online e home office. O de 400 dá conta?', false, 17, now() - interval '5 hours 50 minutes'),
('Dá conta sim! 400 Mbps é mais que suficiente pra tudo isso simultâneo. E nossa fibra tem latência baixíssima, perfeita pra games! 🎮 Quer que eu faça seu cadastro?', true, 17, now() - interval '5 hours 49 minutes'),
('Bora! Meu nome é Thiago Barbosa, CPF 333.444.555-66', false, 17, now() - interval '5 hours 45 minutes'),
('Cadastro iniciado, Thiago! ✅ Vou agendar a visita técnica. Amanhã de manhã ou à tarde fica melhor pra você?', true, 17, now() - interval '5 hours 44 minutes'),

-- Conversa 6: Ana Paula (Lead 2 - FibraNet MG - Lead Morno)
('Oi, quanto custa o plano de 200 mega?', false, 2, now() - interval '1 day'),
('Olá! 😊 O nosso Fibra Plus 200 Mbps sai por R$ 99,90/mês. É ótimo pra streaming e home office! Posso te contar mais detalhes?', true, 2, now() - interval '1 day' + interval '20 seconds'),
('Vou pensar. Tô comparando com outros provedores.', false, 2, now() - interval '23 hours'),
('Sem problemas! 😊 Fica à vontade pra comparar. Só te adianto que temos instalação grátis e sem fidelidade. Qualquer dúvida, é só chamar aqui!', true, 2, now() - interval '23 hours' + interval '15 seconds'),

-- Conversa 7: Pedro Henrique (Lead 10 - ConectaBR - Lead Frio)
('Vocês tem internet em Ipanema?', false, 10, now() - interval '2 days'),
('Temos sim! 🏖️ Ipanema tem cobertura completa da ConectaBR. Nossos planos começam em R$ 69,90. Quer conhecer as opções?', true, 10, now() - interval '2 days' + interval '30 seconds'),

-- Conversa 8: Amanda Freitas (Lead 20 - NordesteFibra - Lead Frio por Indicação)
('Oi, minha amiga Patrícia me indicou vocês. Tem desconto?', false, 20, now() - interval '1 day 5 hours'),
('Oi, Amanda! 🌴 Que legal que a Patrícia indicou! Sim, temos o programa de indicação: você ganha R$ 20 de desconto por 6 meses! Qual plano te interessa?', true, 20, now() - interval '1 day 5 hours' + interval '25 seconds'),
('Ainda não sei. Vou ver os planos no site e volto a falar.', false, 20, now() - interval '1 day 4 hours');

-- ============================================================================
-- PARTE 7: REGISTRO DE CREDENCIAIS GERADAS
-- ============================================================================
-- Salva as apikeys geradas e a senha do banco para consulta posterior
INSERT INTO credenciais_geradas (provedor_nome, instancia, apikey_gerada, senha_banco, notas)
SELECT 
  p.nome_provedor,
  p.instancia,
  p.apikey,
  '3acDZwaNJwPcpozU',
  CASE p.nome_provedor
    WHEN 'FibraNet MG' THEN 'Provedor BH - Plano Profissional - Chatwoot Inbox ID: 1'
    WHEN 'VeloCity Net' THEN 'Provedor SP - Plano Enterprise - Chatwoot Inbox ID: 2'
    WHEN 'ConectaBR Telecom' THEN 'Provedor RJ - Plano Básico - Chatwoot Inbox ID: 3'
    WHEN 'TurboLink RS' THEN 'Provedor POA - Plano Profissional - Chatwoot Inbox ID: 4'
    WHEN 'NordesteFibra' THEN 'Provedor Recife - Plano Básico - Chatwoot Inbox ID: 5'
  END
FROM provedores p
ORDER BY p.id;

-- ============================================================================
-- PARTE 8: ROW LEVEL SECURITY (RLS) - Segurança Supabase
-- ============================================================================

-- Habilitar RLS em todas as tabelas
ALTER TABLE provedores ENABLE ROW LEVEL SECURITY;
ALTER TABLE planos ENABLE ROW LEVEL SECURITY;
ALTER TABLE leads ENABLE ROW LEVEL SECURITY;
ALTER TABLE mensagens ENABLE ROW LEVEL SECURITY;
ALTER TABLE credenciais_geradas ENABLE ROW LEVEL SECURITY;

-- Políticas para service_role (acesso total - usado pelo N8N e backend)
CREATE POLICY "Service role full access provedores" ON provedores
  FOR ALL USING (true) WITH CHECK (true);

CREATE POLICY "Service role full access planos" ON planos
  FOR ALL USING (true) WITH CHECK (true);

CREATE POLICY "Service role full access leads" ON leads
  FOR ALL USING (true) WITH CHECK (true);

CREATE POLICY "Service role full access mensagens" ON mensagens
  FOR ALL USING (true) WITH CHECK (true);

CREATE POLICY "Service role full access credenciais" ON credenciais_geradas
  FOR ALL USING (true) WITH CHECK (true);

-- ============================================================================
-- PARTE 9: FUNÇÕES UTILITÁRIAS
-- ============================================================================

-- Função para buscar lead por número WhatsApp
CREATE OR REPLACE FUNCTION buscar_lead_por_whatsapp(p_remotejid text)
RETURNS TABLE(
  lead_id integer,
  lead_nome text,
  lead_whatsapp text,
  provedor text,
  tags text[]
) AS $$
BEGIN
  RETURN QUERY
  SELECT l.id, l.nome, l.whatsapp, p.nome_provedor, l.tags
  FROM leads l
  JOIN provedores p ON p.id = l.provedor_id
  WHERE l.remotejid = p_remotejid;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Função para registrar nova mensagem
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
  
  -- Atualiza o updated_at do lead
  UPDATE leads SET updated_at = now() WHERE id = p_lead_id;
  
  RETURN v_msg_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Função para obter histórico de conversa de um lead
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
    CASE WHEN m.is_bot THEN 'AGENTE_IA' ELSE 'LEAD' END,
    m.created_at
  FROM mensagens m
  WHERE m.lead_id = p_lead_id
  ORDER BY m.created_at DESC
  LIMIT p_limite;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Função para criar ou atualizar lead (upsert)
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
  -- Tenta encontrar lead existente
  SELECT id INTO v_lead_id FROM leads 
  WHERE remotejid = p_remotejid AND provedor_id = p_provedor_id;
  
  IF v_lead_id IS NOT NULL THEN
    -- Atualiza dados não nulos
    UPDATE leads SET
      nome = COALESCE(p_nome, nome),
      cpf_cnpj = COALESCE(p_cpf_cnpj, cpf_cnpj),
      endereco_instalacao = COALESCE(p_endereco, endereco_instalacao),
      whatsapp = COALESCE(p_whatsapp, whatsapp),
      tags = COALESCE(p_tags, tags),
      updated_at = now()
    WHERE id = v_lead_id;
  ELSE
    -- Cria novo lead
    INSERT INTO leads (nome, cpf_cnpj, endereco_instalacao, remotejid, whatsapp, tags, provedor_id)
    VALUES (p_nome, p_cpf_cnpj, p_endereco, p_remotejid, p_whatsapp, COALESCE(p_tags, ARRAY['novo_lead']), p_provedor_id)
    RETURNING id INTO v_lead_id;
  END IF;
  
  RETURN v_lead_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Função para dashboard resumo
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
    (SELECT COUNT(*) FROM leads WHERE (p_provedor_id IS NULL OR provedor_id = p_provedor_id)),
    (SELECT COUNT(*) FROM leads WHERE 'lead_quente' = ANY(tags) AND (p_provedor_id IS NULL OR provedor_id = p_provedor_id)),
    (SELECT COUNT(*) FROM leads WHERE 'lead_morno' = ANY(tags) AND (p_provedor_id IS NULL OR provedor_id = p_provedor_id)),
    (SELECT COUNT(*) FROM leads WHERE 'lead_frio' = ANY(tags) AND (p_provedor_id IS NULL OR provedor_id = p_provedor_id)),
    (SELECT COUNT(*) FROM mensagens m JOIN leads l ON l.id = m.lead_id WHERE (p_provedor_id IS NULL OR l.provedor_id = p_provedor_id)),
    (SELECT COUNT(*) FROM mensagens m JOIN leads l ON l.id = m.lead_id WHERE m.is_bot = true AND (p_provedor_id IS NULL OR l.provedor_id = p_provedor_id)),
    (SELECT COUNT(*) FROM mensagens m JOIN leads l ON l.id = m.lead_id WHERE m.is_bot = false AND (p_provedor_id IS NULL OR l.provedor_id = p_provedor_id)),
    (SELECT COUNT(*) FROM planos WHERE (p_provedor_id IS NULL OR provedor_id = p_provedor_id)),
    (SELECT MIN(valor) FROM planos WHERE ativo = true AND (p_provedor_id IS NULL OR provedor_id = p_provedor_id)),
    (SELECT MAX(valor) FROM planos WHERE ativo = true AND (p_provedor_id IS NULL OR provedor_id = p_provedor_id));
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- PARTE 10: VIEWS ÚTEIS
-- ============================================================================

-- View de leads com informações do provedor
CREATE OR REPLACE VIEW vw_leads_completo AS
SELECT 
  l.id as lead_id,
  l.nome as lead_nome,
  l.whatsapp,
  l.endereco_instalacao,
  l.tags,
  l.created_at as lead_desde,
  p.nome_provedor,
  p.instancia,
  (SELECT COUNT(*) FROM mensagens m WHERE m.lead_id = l.id) as total_mensagens,
  (SELECT m.created_at FROM mensagens m WHERE m.lead_id = l.id ORDER BY m.created_at DESC LIMIT 1) as ultima_mensagem
FROM leads l
JOIN provedores p ON p.id = l.provedor_id;

-- View de planos com nome do provedor
CREATE OR REPLACE VIEW vw_planos_completo AS
SELECT 
  pl.id as plano_id,
  pl.nome_plano,
  pl.velocidade,
  pl.valor,
  pl.ativo,
  p.nome_provedor,
  p.plano as plano_assinatura
FROM planos pl
JOIN provedores p ON p.id = pl.provedor_id
ORDER BY p.nome_provedor, pl.valor;

-- View de conversas formatadas
CREATE OR REPLACE VIEW vw_conversas AS
SELECT 
  m.id as msg_id,
  l.nome as lead_nome,
  l.whatsapp,
  p.nome_provedor,
  m.mensagem,
  CASE WHEN m.is_bot THEN '🤖 Agente IA' ELSE '👤 Lead' END as remetente,
  m.created_at as enviada_em
FROM mensagens m
JOIN leads l ON l.id = m.lead_id
JOIN provedores p ON p.id = l.provedor_id
ORDER BY m.created_at DESC;

-- ============================================================================
-- PARTE 11: VERIFICAÇÃO FINAL
-- ============================================================================
DO $$
DECLARE
  v_provedores integer;
  v_planos integer;
  v_leads integer;
  v_mensagens integer;
  v_credenciais integer;
BEGIN
  SELECT COUNT(*) INTO v_provedores FROM provedores;
  SELECT COUNT(*) INTO v_planos FROM planos;
  SELECT COUNT(*) INTO v_leads FROM leads;
  SELECT COUNT(*) INTO v_mensagens FROM mensagens;
  SELECT COUNT(*) INTO v_credenciais FROM credenciais_geradas;
  
  RAISE NOTICE '============================================';
  RAISE NOTICE 'SETUP COMPLETO COM SUCESSO!';
  RAISE NOTICE '============================================';
  RAISE NOTICE 'Provedores criados: %', v_provedores;
  RAISE NOTICE 'Planos criados: %', v_planos;
  RAISE NOTICE 'Leads criados: %', v_leads;
  RAISE NOTICE 'Mensagens criadas: %', v_mensagens;
  RAISE NOTICE 'Credenciais salvas: %', v_credenciais;
  RAISE NOTICE '============================================';
  RAISE NOTICE 'PRÓXIMO PASSO: Execute SELECT * FROM credenciais_geradas;';
  RAISE NOTICE 'para obter as apikeys geradas para uso no Chatwoot e N8N';
  RAISE NOTICE '============================================';
END $$;
