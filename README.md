# Agente Comercial ISP - Base de Dados

Sistema de banco de dados para automação comercial de provedores de internet (ISP) via WhatsApp com Inteligência Artificial. Projetado para rodar na VPS junto com a infraestrutura **br10ia_versaofinal_auto** (Docker Swarm + Portainer + PostgreSQL + N8N + Chatwoot).

## Visão Geral

Este repositório contém os scripts para criar e popular automaticamente o banco de dados `agente_comercial` no PostgreSQL da VPS, sem necessidade de Supabase. Tudo roda localmente no mesmo PostgreSQL que já serve o N8N e o Chatwoot.

```
PostgreSQL (pgvector:pg17)
├── postgres    (sistema)
├── n8n         (já existente)
├── chatwoot    (já existente)
└── agente_comercial  ← ESTE PROJETO
```

## Estrutura do Banco

```
provedores (1) ──── (N) planos
     │
     └──── (N) leads (1) ──── (N) mensagens
```

| Tabela | Descrição | Registros |
|--------|-----------|-----------|
| `provedores` | Provedores ISP com config de IA (JSONB) | 5 |
| `planos` | Planos de internet por provedor | 25 |
| `leads` | Leads capturados via WhatsApp | 20 |
| `mensagens` | Histórico de conversas com agente IA | 42 |

## Deploy na VPS

Existem **duas formas** de fazer o deploy. Escolha a que preferir.

### Opção A: Deploy via Script Bash (Recomendado)

O script detecta automaticamente o container PostgreSQL e executa tudo.

```bash
# 1. Clone o repositório na VPS
git clone https://github.com/Br10Consultoria/agent_comercial.git
cd agent_comercial

# 2. Execute o deploy
sudo bash scripts/deploy-database.sh --senha 3acDZwaNJwPcpozU

# 3. Consulte as credenciais geradas
cat /etc/agente-comercial/.credentials
```

O script aceita as seguintes opções:

| Opção | Descrição |
|-------|-----------|
| `--senha SENHA` | Define a senha do user `agente_comercial` |
| `--pg-senha SENHA` | Senha do user `postgres` (se necessário) |
| `--reset` | Remove e recria o database do zero |
| `--apenas-dados` | Apenas repopula os dados sem recriar tabelas |
| `--container NOME` | Nome do container PostgreSQL (se não detectar automaticamente) |

### Opção B: Deploy via Portainer API

Segue o mesmo padrão do `deploy-stacks.sh` do br10ia. Cria uma stack no Portainer e depois executa os SQLs.

```bash
cd agent_comercial
sudo bash scripts/deploy-via-portainer.sh
```

### Opção C: Deploy Manual (passo a passo)

Se preferir executar manualmente no container PostgreSQL:

```bash
# Descobrir o container
docker ps | grep postgres

# Criar o database
docker exec -e PGPASSWORD=SUA_SENHA CONTAINER \
  psql -U postgres -c "CREATE DATABASE agente_comercial"

# Executar cada SQL na ordem
docker exec -i -e PGPASSWORD=SUA_SENHA CONTAINER \
  psql -U postgres -d agente_comercial < sql/01_ddl.sql

docker exec -i -e PGPASSWORD=SUA_SENHA CONTAINER \
  psql -U postgres -d agente_comercial < sql/02_dados.sql

docker exec -i -e PGPASSWORD=SUA_SENHA CONTAINER \
  psql -U postgres -d agente_comercial < sql/03_funcoes_views.sql
```

## Credenciais

Após o deploy, todas as credenciais ficam salvas em `/etc/agente-comercial/.credentials` com permissão `600` (somente root). O arquivo contém:

- Dados de conexão PostgreSQL (host, porta, database, user, senha)
- Connection string pronta para uso
- APIKeys geradas automaticamente para cada provedor (64 caracteres hex)

## Integração com N8N

No node **Postgres** do N8N, use as seguintes configurações:

| Campo | Valor |
|-------|-------|
| Host | `postgres` |
| Port | `5432` |
| Database | `agente_comercial` |
| User | `agente_comercial` |
| Password | (ver `/etc/agente-comercial/.credentials`) |
| SSL | Desabilitado (rede interna Docker) |

Para chamar as funções via N8N, use o node **Execute Query**:

```sql
-- Buscar lead quando receber mensagem no WhatsApp
SELECT * FROM buscar_lead_por_whatsapp('5511999999999@s.whatsapp.net');

-- Obter config do bot pela instância
SELECT * FROM buscar_config_bot('fibranet_mg_whatsapp');

-- Registrar mensagem recebida
SELECT registrar_mensagem(1, 'Texto da mensagem', false);

-- Registrar resposta do bot
SELECT registrar_mensagem(1, 'Resposta do agente', true);

-- Obter histórico para contexto da IA
SELECT * FROM historico_conversa(1, 20);

-- Criar/atualizar lead
SELECT upsert_lead('5511999999999@s.whatsapp.net', 1, 'Nome do Lead');

-- Listar planos para o agente apresentar
SELECT * FROM listar_planos_provedor(1);
```

## Integração com Chatwoot

Cada provedor possui um `chatwoot_inbox_id` no campo `config_bot` (JSONB). O fluxo típico é:

1. Mensagem chega no Chatwoot via WhatsApp
2. Webhook dispara para o N8N
3. N8N consulta `buscar_lead_por_whatsapp()` e `buscar_config_bot()`
4. N8N envia histórico + prompt para a IA
5. IA responde e N8N registra via `registrar_mensagem()`

## Funções Disponíveis

| Função | Uso | Descrição |
|--------|-----|-----------|
| `buscar_lead_por_whatsapp(remotejid)` | N8N | Busca lead pelo JID do WhatsApp |
| `buscar_config_bot(instancia)` | N8N | Retorna config JSONB do agente IA |
| `registrar_mensagem(lead_id, msg, is_bot)` | N8N | Registra mensagem na conversa |
| `historico_conversa(lead_id, limite)` | N8N/IA | Histórico formatado (role: user/assistant) |
| `upsert_lead(remotejid, provedor_id, ...)` | N8N | Cria ou atualiza lead |
| `listar_planos_provedor(provedor_id)` | N8N/IA | Lista planos ativos do provedor |
| `atualizar_tags_lead(lead_id, tags)` | N8N | Atualiza qualificação do lead |
| `dashboard_resumo(provedor_id)` | Admin | Métricas do sistema |

## Views Disponíveis

| View | Descrição |
|------|-----------|
| `vw_leads_completo` | Leads com info do provedor e contagem de mensagens |
| `vw_planos_completo` | Planos com nome do provedor |
| `vw_conversas` | Conversas formatadas com remetente identificado |
| `vw_resumo_provedores` | Dashboard por provedor com métricas |

## Estrutura de Arquivos

```
agent_comercial/
├── README.md
├── scripts/
│   ├── deploy-database.sh          # Deploy principal via docker exec
│   └── deploy-via-portainer.sh     # Deploy alternativo via Portainer API
├── sql/
│   ├── 01_ddl.sql                  # Tabelas, índices, FKs, triggers
│   ├── 02_dados.sql                # Provedores, planos, leads, mensagens
│   ├── 03_funcoes_views.sql        # Funções e views utilitárias
│   └── 04_queries_pratica.sql      # Queries de prática (básico ao avançado)
└── stacks/
    └── agente-comercial-init       # Stack Portainer (cria DB e user)
```

## Licença

Projeto educacional - Br10 Consultoria.
