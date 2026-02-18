-- ============================================================================
-- AGENTE COMERCIAL ISP - Dados de População
-- ============================================================================
-- Provedores com apikeys geradas, planos, leads e mensagens
-- Executado automaticamente pelo deploy-database.sh
-- ============================================================================

BEGIN;

-- ============================================================================
-- PROVEDORES (apikeys geradas com gen_random_bytes)
-- ============================================================================
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
    "prompt_boas_vindas": "Olá! Sou o assistente virtual da FibraNet MG! Temos os melhores planos de fibra óptica de BH. Como posso te ajudar hoje?",
    "horario_atendimento": {"inicio": "08:00", "fim": "22:00"},
    "webhook_n8n": "https://webhook.SEUDOMINIO.com.br/webhook/fibranet-whatsapp",
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
    "prompt_boas_vindas": "Bem-vindo à VeloCity Net! Internet ultra rápida pra SP inteira. Bora encontrar o plano perfeito pra você?",
    "horario_atendimento": {"inicio": "07:00", "fim": "23:00"},
    "webhook_n8n": "https://webhook.SEUDOMINIO.com.br/webhook/velocity-whatsapp",
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
    "prompt_boas_vindas": "Fala! Aqui é da ConectaBR Telecom! Internet fibra óptica no RJ inteiro. Como posso te ajudar?",
    "horario_atendimento": {"inicio": "08:00", "fim": "21:00"},
    "webhook_n8n": "https://webhook.SEUDOMINIO.com.br/webhook/conectabr-whatsapp",
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
    "prompt_boas_vindas": "Bem-vindo à TurboLink RS! A melhor internet fibra do Sul. Em que posso te ajudar?",
    "horario_atendimento": {"inicio": "08:00", "fim": "22:00"},
    "webhook_n8n": "https://webhook.SEUDOMINIO.com.br/webhook/turbolink-whatsapp",
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
    "prompt_boas_vindas": "Oi, tudo bem? Aqui é da NordesteFibra! A internet mais arretada de Recife! Como posso te ajudar?",
    "horario_atendimento": {"inicio": "07:30", "fim": "21:30"},
    "webhook_n8n": "https://webhook.SEUDOMINIO.com.br/webhook/nordestefibra-whatsapp",
    "chatwoot_inbox_id": 5
  }'::jsonb,
  'basico',
  true
);

-- ============================================================================
-- PLANOS DE INTERNET (5 por provedor = 25 planos)
-- ============================================================================
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

-- ============================================================================
-- LEADS (20 leads distribuídos entre provedores)
-- ============================================================================
INSERT INTO leads (nome, cpf_cnpj, endereco_instalacao, remotejid, whatsapp, tags, provedor_id) VALUES
-- FibraNet MG (provedor_id = 1)
('Carlos Eduardo Silva',    '123.456.789-00',     'Rua dos Inconfidentes, 450, Savassi, Belo Horizonte - MG',       '553199887766@s.whatsapp.net',  '(31) 99988-7766', ARRAY['lead_quente', 'residencial', 'fibra_giga'],      1),
('Ana Paula Oliveira',      '234.567.890-11',     'Av. Afonso Pena, 1200, Centro, Belo Horizonte - MG',             '553198776655@s.whatsapp.net',  '(31) 98877-6655', ARRAY['lead_morno', 'residencial'],                     1),
('Roberto Mendes Ltda',     '12.345.678/0001-90', 'Rua Espírito Santo, 800, Centro, Belo Horizonte - MG',           '553197665544@s.whatsapp.net',  '(31) 97766-5544', ARRAY['lead_quente', 'empresarial', 'fibra_giga'],      1),
('Fernanda Costa Santos',   '345.678.901-22',     'Rua Rio de Janeiro, 1500, Lourdes, Belo Horizonte - MG',         '553196554433@s.whatsapp.net',  '(31) 96655-4433', ARRAY['lead_frio', 'residencial'],                      1),

-- VeloCity Net (provedor_id = 2)
('João Pedro Nakamura',     '456.789.012-33',     'Av. Paulista, 1578, Bela Vista, São Paulo - SP',                 '5511987654321@s.whatsapp.net', '(11) 98765-4321', ARRAY['lead_quente', 'empresarial', 'speed_giga'],      2),
('Maria Luísa Ferreira',    '567.890.123-44',     'Rua Augusta, 2300, Consolação, São Paulo - SP',                  '5511976543210@s.whatsapp.net', '(11) 97654-3210', ARRAY['lead_morno', 'residencial', 'streaming'],        2),
('Tech Solutions SP Ltda',  '23.456.789/0001-01', 'Av. Faria Lima, 3000, Pinheiros, São Paulo - SP',                '5511965432109@s.whatsapp.net', '(11) 96543-2109', ARRAY['lead_quente', 'empresarial', 'link_dedicado'],   2),
('Lucas Gabriel Souza',     '678.901.234-55',     'Rua Oscar Freire, 900, Jardins, São Paulo - SP',                 '5511954321098@s.whatsapp.net', '(11) 95432-1098', ARRAY['lead_morno', 'residencial', 'gaming'],           2),

-- ConectaBR Telecom (provedor_id = 3)
('Rafaela Almeida',         '789.012.345-66',     'Av. Atlântica, 2500, Copacabana, Rio de Janeiro - RJ',           '5521998877665@s.whatsapp.net', '(21) 99887-7665', ARRAY['lead_quente', 'residencial'],                    3),
('Pedro Henrique Lima',     '890.123.456-77',     'Rua Visconde de Pirajá, 300, Ipanema, Rio de Janeiro - RJ',      '5521987766554@s.whatsapp.net', '(21) 98776-6554', ARRAY['lead_frio', 'residencial'],                      3),
('Escritório Carioca Adv',  '34.567.890/0001-12', 'Av. Rio Branco, 156, Centro, Rio de Janeiro - RJ',               '5521976655443@s.whatsapp.net', '(21) 97665-5443', ARRAY['lead_quente', 'empresarial'],                    3),
('Camila Rodrigues',        '901.234.567-88',     'Rua das Laranjeiras, 450, Laranjeiras, Rio de Janeiro - RJ',     '5521965544332@s.whatsapp.net', '(21) 96554-4332', ARRAY['lead_morno', 'residencial', 'home_office'],      3),

-- TurboLink RS (provedor_id = 4)
('Marcos Vinícius Becker',  '012.345.678-99',     'Rua dos Andradas, 1200, Centro Histórico, Porto Alegre - RS',    '5551998877665@s.whatsapp.net', '(51) 99887-7665', ARRAY['lead_quente', 'residencial', 'turbo_giga'],      4),
('Juliana Schneider',       '111.222.333-44',     'Av. Ipiranga, 6681, Partenon, Porto Alegre - RS',                '5551987766554@s.whatsapp.net', '(51) 98776-6554', ARRAY['lead_morno', 'residencial'],                     4),
('Gaúcha Tech ME',          '45.678.901/0001-23', 'Rua Voluntários da Pátria, 800, Centro, Porto Alegre - RS',      '5551976655443@s.whatsapp.net', '(51) 97665-5443', ARRAY['lead_quente', 'empresarial', 'turbo_business'],  4),
('Ricardo Azevedo',         '222.333.444-55',     'Av. Protásio Alves, 3000, Petrópolis, Porto Alegre - RS',        '5551965544332@s.whatsapp.net', '(51) 96554-4332', ARRAY['lead_frio', 'residencial'],                      4),

-- NordesteFibra (provedor_id = 5)
('Thiago Barbosa',          '333.444.555-66',     'Av. Boa Viagem, 4500, Boa Viagem, Recife - PE',                  '5581998877665@s.whatsapp.net', '(81) 99887-7665', ARRAY['lead_quente', 'residencial', 'nordeste_giga'],   5),
('Patrícia Cavalcanti',     '444.555.666-77',     'Rua do Bom Jesus, 200, Recife Antigo, Recife - PE',              '5581987766554@s.whatsapp.net', '(81) 98776-6554', ARRAY['lead_morno', 'residencial'],                     5),
('Recife Digital Ltda',     '56.789.012/0001-34', 'Av. Agamenon Magalhães, 1500, Derby, Recife - PE',               '5581976655443@s.whatsapp.net', '(81) 97665-5443', ARRAY['lead_quente', 'empresarial'],                    5),
('Amanda Freitas',          '555.666.777-88',     'Rua da Aurora, 350, Boa Vista, Recife - PE',                      '5581965544332@s.whatsapp.net', '(81) 96554-4332', ARRAY['lead_frio', 'residencial', 'indicacao'],         5);

-- ============================================================================
-- MENSAGENS (conversas realistas de atendimento via WhatsApp)
-- ============================================================================

-- Conversa 1: Carlos Eduardo (Lead 1 - FibraNet MG - Lead Quente)
INSERT INTO mensagens (mensagem, is_bot, lead_id, created_at) VALUES
('Oi, boa tarde! Vi o anúncio de vocês no Instagram. Quero saber sobre os planos de internet.', false, 1, now() - interval '2 hours'),
('Olá, Carlos! Que bom que nos encontrou! Sou o assistente virtual da FibraNet MG. Temos planos de fibra óptica de 100 Mbps até 1 Gbps. Pra eu te indicar o melhor plano, me conta: o uso seria residencial ou empresarial?', true, 1, now() - interval '2 hours' + interval '30 seconds'),
('Residencial mesmo. Somos em 4 pessoas em casa, todo mundo usa streaming e eu faço home office.', false, 1, now() - interval '1 hour 55 minutes'),
('Perfeito! Com 4 pessoas usando streaming e home office, recomendo nosso plano Fibra Ultra 600 Mbps por R$ 169,90/mês ou o Fibra Giga 1 Gbps por R$ 219,90/mês. Ambos garantem estabilidade pra todo mundo. Qual te interessa mais?', true, 1, now() - interval '1 hour 54 minutes'),
('O Fibra Giga parece bom. Qual o prazo de instalação?', false, 1, now() - interval '1 hour 50 minutes'),
('Ótima escolha! O Fibra Giga tem instalação em até 48h úteis. Pra verificar a cobertura e agendar, preciso do seu endereço completo. Pode me informar?', true, 1, now() - interval '1 hour 49 minutes'),
('Rua dos Inconfidentes, 450, Savassi, BH', false, 1, now() - interval '1 hour 45 minutes'),
('Excelente! A Savassi tem cobertura total da nossa fibra! Pra finalizar o cadastro, preciso do seu nome completo e CPF. Pode me passar?', true, 1, now() - interval '1 hour 44 minutes'),
('Carlos Eduardo Silva, CPF 123.456.789-00', false, 1, now() - interval '1 hour 40 minutes'),
('Perfeito, Carlos! Cadastro realizado com sucesso! Vou encaminhar para nossa equipe técnica agendar a instalação. Você prefere manhã ou tarde?', true, 1, now() - interval '1 hour 39 minutes'),

-- Conversa 2: João Pedro (Lead 5 - VeloCity Net - Lead Quente Empresarial)
('Preciso de internet empresarial pra meu escritório na Paulista. Vocês atendem?', false, 5, now() - interval '3 hours'),
('Olá! Claro que atendemos! A Av. Paulista é uma das nossas áreas com melhor cobertura. Sou o assistente da VeloCity Net. Pra empresas, temos planos a partir de 200 Mbps com IP fixo. Quantos colaboradores usam a internet no escritório?', true, 5, now() - interval '3 hours' + interval '25 seconds'),
('Somos uns 15 funcionários. Precisamos de algo bem estável, usamos sistemas em nuvem e videoconferência o dia todo.', false, 5, now() - interval '2 hours 55 minutes'),
('Com 15 colaboradores usando nuvem e vídeo, recomendo nosso Speed Giga Pro 2 Gbps por R$ 349,90/mês. Inclui IP fixo, SLA de 99,5% e suporte prioritário. Quer que eu detalhe?', true, 5, now() - interval '2 hours 54 minutes'),
('Sim, me manda os detalhes. E qual o CNPJ de vocês pra eu verificar?', false, 5, now() - interval '2 hours 50 minutes'),
('O Speed Giga Pro inclui: 2 Gbps simétricos, IP fixo dedicado, SLA 99,5% com multa, Suporte 24/7 prioritário, Instalação em até 5 dias úteis. Posso agendar uma visita técnica?', true, 5, now() - interval '2 hours 49 minutes'),

-- Conversa 3: Rafaela Almeida (Lead 9 - ConectaBR - Lead Quente)
('Boa noite! Acabei de me mudar pra Copacabana e preciso de internet urgente!', false, 9, now() - interval '5 hours'),
('Boa noite, bem-vinda a Copacabana! Sou da ConectaBR Telecom. Temos cobertura total em Copa! Pra uso residencial, nossos planos vão de 100 Mbps a 1 Gbps. O que você mais usa? Streaming, home office, games?', true, 9, now() - interval '5 hours' + interval '20 seconds'),
('Uso bastante Netflix e trabalho de casa 3x por semana. Quero algo bom mas sem pagar muito caro.', false, 9, now() - interval '4 hours 55 minutes'),
('Entendi perfeitamente! Pra Netflix + home office, o Conecta 300 por R$ 99,90/mês é ideal! E temos uma promoção: na fidelidade de 12 meses, sai por R$ 89,90/mês. Quer aproveitar?', true, 9, now() - interval '4 hours 54 minutes'),
('Esse preço tá ótimo! Quero sim! Como faço?', false, 9, now() - interval '4 hours 50 minutes'),
('Maravilha! Me passa seu nome completo, CPF e o endereço exato com número do apartamento que já inicio seu cadastro!', true, 9, now() - interval '4 hours 49 minutes'),

-- Conversa 4: Marcos Vinícius (Lead 13 - TurboLink RS - Lead Quente)
('Buenas! Tô querendo trocar de provedor. A internet aqui tá muito ruim.', false, 13, now() - interval '4 hours'),
('Entendo a frustração! Sou o assistente da TurboLink RS. Vamos resolver isso! Me conta: qual velocidade você tem hoje e o que precisa?', true, 13, now() - interval '4 hours' + interval '30 seconds'),
('Tenho 100 mega mas não chega nem na metade. Preciso de algo que funcione de verdade.', false, 13, now() - interval '3 hours 55 minutes'),
('Na TurboLink usamos fibra óptica FTTH, que entrega velocidade real. Recomendo o Turbo 300 por R$ 104,90/mês - é o mais pedido! E nosso diferencial: suporte técnico 24h com atendimento humano. Quer testar?', true, 13, now() - interval '3 hours 54 minutes'),
('Suporte 24h é bom demais. Mas vocês cobram instalação?', false, 13, now() - interval '3 hours 50 minutes'),
('Instalação é GRÁTIS! E o roteador Wi-Fi 6 já tá incluso em comodato. Sem surpresas na fatura! Me passa teu endereço que verifico a cobertura na hora.', true, 13, now() - interval '3 hours 49 minutes'),

-- Conversa 5: Thiago Barbosa (Lead 17 - NordesteFibra - Lead Quente)
('Eae, vi que vocês tem internet fibra em Boa Viagem. Quanto tá o plano mais rápido?', false, 17, now() - interval '6 hours'),
('Oi! Nosso plano top é o Nordeste Giga 1 Gbps por R$ 199,90/mês! É o mais arretado de Recife! Você mora em Boa Viagem mesmo?', true, 17, now() - interval '6 hours' + interval '25 seconds'),
('Moro sim, na Av. Boa Viagem, 4500. Mas achei caro. Tem algo mais em conta?', false, 17, now() - interval '5 hours 55 minutes'),
('Claro! Temos o Nordeste 400 por R$ 109,90/mês que é excelente! E olha: se você indicar um amigo, ganha R$ 20 de desconto por 6 meses! Pra que você mais usa a internet?', true, 17, now() - interval '5 hours 54 minutes'),
('Uso pra streaming, jogo online e home office. O de 400 dá conta?', false, 17, now() - interval '5 hours 50 minutes'),
('Dá conta sim! 400 Mbps é mais que suficiente pra tudo isso simultâneo. E nossa fibra tem latência baixíssima, perfeita pra games! Quer que eu faça seu cadastro?', true, 17, now() - interval '5 hours 49 minutes'),
('Bora! Meu nome é Thiago Barbosa, CPF 333.444.555-66', false, 17, now() - interval '5 hours 45 minutes'),
('Cadastro iniciado, Thiago! Vou agendar a visita técnica. Amanhã de manhã ou à tarde fica melhor pra você?', true, 17, now() - interval '5 hours 44 minutes'),

-- Conversa 6: Ana Paula (Lead 2 - FibraNet MG - Lead Morno)
('Oi, quanto custa o plano de 200 mega?', false, 2, now() - interval '1 day'),
('Olá! O nosso Fibra Plus 200 Mbps sai por R$ 99,90/mês. É ótimo pra streaming e home office! Posso te contar mais detalhes?', true, 2, now() - interval '1 day' + interval '20 seconds'),
('Vou pensar. Tô comparando com outros provedores.', false, 2, now() - interval '23 hours'),
('Sem problemas! Fica à vontade pra comparar. Só te adianto que temos instalação grátis e sem fidelidade. Qualquer dúvida, é só chamar aqui!', true, 2, now() - interval '23 hours' + interval '15 seconds'),

-- Conversa 7: Pedro Henrique (Lead 10 - ConectaBR - Lead Frio)
('Vocês tem internet em Ipanema?', false, 10, now() - interval '2 days'),
('Temos sim! Ipanema tem cobertura completa da ConectaBR. Nossos planos começam em R$ 69,90. Quer conhecer as opções?', true, 10, now() - interval '2 days' + interval '30 seconds'),

-- Conversa 8: Amanda Freitas (Lead 20 - NordesteFibra - Lead Frio por Indicação)
('Oi, minha amiga Patrícia me indicou vocês. Tem desconto?', false, 20, now() - interval '1 day 5 hours'),
('Oi, Amanda! Que legal que a Patrícia indicou! Sim, temos o programa de indicação: você ganha R$ 20 de desconto por 6 meses! Qual plano te interessa?', true, 20, now() - interval '1 day 5 hours' + interval '25 seconds'),
('Ainda não sei. Vou ver os planos no site e volto a falar.', false, 20, now() - interval '1 day 4 hours');

COMMIT;
