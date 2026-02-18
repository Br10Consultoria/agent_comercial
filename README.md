# Agente Comercial ISP - Base de Dados

Sistema de banco de dados para automação comercial de provedores de internet (ISP) via WhatsApp com Inteligência Artificial.

## Visão Geral

Este projeto contém os scripts SQL para criar e popular um banco de dados completo no **Supabase** (PostgreSQL), projetado para integrar com:

- **WhatsApp** (Evolution API / Chatwoot)
- **N8N** (automação de workflows)
- **Chatwoot** (atendimento multicanal)
- **OpenAI / LLMs** (agentes IA comerciais)

## Estrutura do Banco

```
provedores (1) ──── (N) planos
     │
     └──── (N) leads (1) ──── (N) mensagens
```

### Tabelas

| Tabela | Descrição | Registros |
|--------|-----------|-----------|
| `provedores` | Provedores ISP com config de IA (JSONB) | 5 |
| `planos` | Planos de internet por provedor | 25 |
| `leads` | Leads capturados via WhatsApp | 20 |
| `mensagens` | Histórico de conversas com agente IA | 42 |
| `credenciais_geradas` | APIKeys e senhas para consulta | 5 |

### Provedores Incluídos

| Provedor | Região | Plano | Instância WhatsApp |
|----------|--------|-------|--------------------|
| FibraNet MG | Belo Horizonte - MG | Profissional | `fibranet_mg_whatsapp` |
| VeloCity Net | São Paulo - SP | Enterprise | `velocity_sp_whatsapp` |
| ConectaBR Telecom | Rio de Janeiro - RJ | Básico | `conectabr_rj_whatsapp` |
| TurboLink RS | Porto Alegre - RS | Profissional | `turbolink_rs_whatsapp` |
| NordesteFibra | Recife - PE | Básico | `nordestefibra_pe_whatsapp` |

## Como Usar

### Pré-requisitos

- Conta no [Supabase](https://supabase.com) (gratuita)
- Projeto criado no Supabase

### Passo a Passo

1. **Acesse o Supabase SQL Editor**
   - Entre em [supabase.com](https://supabase.com)
   - Abra seu projeto
   - Vá em **SQL Editor** no menu lateral

2. **Execute o script principal**
   - Abra o arquivo `sql/01_setup_completo.sql`
   - Cole todo o conteúdo no SQL Editor
   - Clique em **Run**

3. **Consulte as credenciais geradas**
   - Execute: `SELECT * FROM credenciais_geradas;`
   - Anote as `apikey_gerada` de cada provedor
   - Use essas chaves no Chatwoot, N8N e demais integrações

4. **Pratique com as queries**
   - Use o arquivo `sql/03_queries_pratica.sql` para exercícios

## Segurança

### APIKeys
As apikeys são geradas automaticamente usando `gen_random_bytes(32)` do PostgreSQL (criptograficamente seguras). Cada provedor recebe uma apikey única de 64 caracteres hexadecimais.

### Row Level Security (RLS)
Todas as tabelas possuem RLS habilitado. As políticas padrão permitem acesso via `service_role` (usado pelo N8N e backend).

### Senha do Banco
A senha do banco está salva na tabela `credenciais_geradas` para referência.

## Funcionalidades Extras

### Funções PostgreSQL

| Função | Descrição | Uso |
|--------|-----------|-----|
| `buscar_lead_por_whatsapp(remotejid)` | Busca lead pelo JID do WhatsApp | N8N / Chatwoot |
| `registrar_mensagem(lead_id, msg, is_bot)` | Registra nova mensagem | N8N Webhook |
| `historico_conversa(lead_id, limite)` | Retorna histórico formatado | Contexto para IA |
| `upsert_lead(...)` | Cria ou atualiza lead | N8N / API |
| `dashboard_resumo(provedor_id)` | Dashboard com métricas | Painel admin |

### Views

| View | Descrição |
|------|-----------|
| `vw_leads_completo` | Leads com info do provedor e contagem de mensagens |
| `vw_planos_completo` | Planos com nome do provedor |
| `vw_conversas` | Conversas formatadas com remetente identificado |

### Triggers

- **`updated_at` automático**: Todas as tabelas com `updated_at` são atualizadas automaticamente em cada UPDATE.

## Integração com N8N

Para integrar com N8N, use a `service_role_key` do Supabase:

```javascript
// Exemplo de chamada via HTTP Request no N8N
// URL: https://SEU_PROJETO.supabase.co/rest/v1/rpc/registrar_mensagem
// Headers:
//   apikey: SUA_ANON_KEY
//   Authorization: Bearer SUA_SERVICE_ROLE_KEY
//   Content-Type: application/json
// Body:
{
  "p_lead_id": 1,
  "p_mensagem": "Texto da mensagem",
  "p_is_bot": true
}
```

## Integração com Chatwoot

Cada provedor possui um `chatwoot_inbox_id` configurado no campo `config_bot` (JSONB). Use esse ID para rotear mensagens para a inbox correta.

## Estrutura de Arquivos

```
agent_comercial/
├── README.md                          # Esta documentação
└── sql/
    ├── 01_setup_completo.sql          # Script principal (DDL + dados + segurança)
    ├── 02_consultar_credenciais.sql   # Consulta de credenciais geradas
    └── 03_queries_pratica.sql         # Queries de prática (básico ao avançado)
```

## Licença

Projeto educacional - Br10 Consultoria.
