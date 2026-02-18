#!/usr/bin/env bash
#==============================================================================
# AGENTE COMERCIAL ISP - Deploy via Portainer API
#==============================================================================
# Alternativa ao deploy-database.sh: usa a API do Portainer para criar
# a stack de inicialização, seguindo o mesmo padrão do br10ia_versaofinal_auto
#
# Uso:
#   sudo bash deploy-via-portainer.sh
#
# Pré-requisitos:
#   - Portainer rodando em http://127.0.0.1:9000
#   - PostgreSQL já deployado via stack "Postgres"
#   - get-portainer-info.sh configurado
#==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
STACKS_DIR="$SCRIPT_DIR/../stacks"
SQL_DIR="$SCRIPT_DIR/../sql"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info()  { echo -e "${BLUE}[INFO]${NC}  $1"; }
log_ok()    { echo -e "${GREEN}[OK]${NC}    $1"; }
log_warn()  { echo -e "${YELLOW}[AVISO]${NC} $1"; }
log_error() { echo -e "${RED}[ERRO]${NC}  $1"; }
log_step()  { echo -e "\n${CYAN}═══ $1 ═══${NC}"; }
die()       { log_error "$1"; exit 1; }

echo -e "${BLUE}"
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║   AGENTE COMERCIAL ISP - Deploy via Portainer               ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# ─── ETAPA 1: Obter credenciais do Portainer ───────────────────────────────
log_step "ETAPA 1/4: Autenticando no Portainer"

PORTAINER_URL="http://127.0.0.1:9000"

# Tenta ler credenciais do get-portainer-info.sh existente
GET_INFO_SCRIPT=""
for path in \
  "/root/br10ia_versaofinal_auto/get-portainer-info.sh" \
  "/home/*/br10ia_versaofinal_auto/get-portainer-info.sh" \
  "$SCRIPT_DIR/../../br10ia_versaofinal_auto/get-portainer-info.sh"; do
  found=$(ls $path 2>/dev/null | head -1 || true)
  if [[ -n "$found" && -f "$found" ]]; then
    GET_INFO_SCRIPT="$found"
    break
  fi
done

if [[ -n "$GET_INFO_SCRIPT" ]]; then
  log_info "Usando: $GET_INFO_SCRIPT"
  INFO_OUTPUT="$($GET_INFO_SCRIPT 2>/dev/null)"
  
  TOKEN=$(echo "$INFO_OUTPUT" | awk '/^TOKEN:/{getline; print}' | tr -d '\n\r' | xargs)
  ENDPOINT_ID=$(echo "$INFO_OUTPUT" | awk '/endpointId:/{getline; print}' | tr -d '\n\r' | xargs)
  SWARM_ID=$(echo "$INFO_OUTPUT" | awk '/SwarmID:/{getline; print; exit}' | tr -d '\n\r' | xargs)
else
  log_warn "get-portainer-info.sh não encontrado. Tentando login direto..."
  
  read -rp "Portainer user [admin]: " PUSER
  PUSER="${PUSER:-admin}"
  read -rsp "Portainer password: " PPASS
  echo
  
  LOGIN_RESP=$(curl -s -X POST "$PORTAINER_URL/api/auth" \
    -H "Content-Type: application/json" \
    -d "{\"Username\":\"$PUSER\",\"Password\":\"$PPASS\"}")
  
  TOKEN=$(echo "$LOGIN_RESP" | jq -r '.jwt // empty')
  [[ -z "$TOKEN" ]] && die "Falha no login do Portainer"
  
  ENDPOINTS=$(curl -s -X GET "$PORTAINER_URL/api/endpoints" -H "Authorization: Bearer $TOKEN")
  ENDPOINT_ID=$(echo "$ENDPOINTS" | jq -r '.[0].Id // empty')
  
  SWARM_ID=$(docker info --format '{{.Swarm.Cluster.ID}}' 2>/dev/null || true)
fi

[[ -z "$TOKEN" || -z "$ENDPOINT_ID" || -z "$SWARM_ID" ]] && die "Não foi possível obter TOKEN/endpointId/SwarmID"

log_ok "Autenticado no Portainer"
log_ok "Endpoint: $ENDPOINT_ID | Swarm: $SWARM_ID"

# ─── ETAPA 2: Deploy da stack de init ──────────────────────────────────────
log_step "ETAPA 2/4: Deployando stack agente-comercial-init"

STACK_NAME="agente-comercial-init"
STACK_FILE="$STACKS_DIR/$STACK_NAME"

[[ -f "$STACK_FILE" ]] || die "Stack não encontrada: $STACK_FILE"

# Remover stack existente
STACKS_LIST=$(curl -s -X GET "$PORTAINER_URL/api/stacks" -H "Authorization: Bearer $TOKEN")
STACK_ID=$(echo "$STACKS_LIST" | jq -r ".[] | select(.Name == \"$STACK_NAME\") | select(.EndpointId == $ENDPOINT_ID) | .Id" 2>/dev/null || true)

if [[ -n "$STACK_ID" && "$STACK_ID" != "null" ]]; then
  log_info "Removendo stack existente (ID: $STACK_ID)..."
  curl -s -X DELETE "$PORTAINER_URL/api/stacks/$STACK_ID?endpointId=$ENDPOINT_ID" \
    -H "Authorization: Bearer $TOKEN" >/dev/null 2>&1
  sleep 5
fi

# Criar stack
STACK_JSON=$(jq -Rs . < "$STACK_FILE")

RESPONSE=$(curl -s -w "\nHTTP_STATUS:%{http_code}" \
  -X POST "$PORTAINER_URL/api/stacks/create/swarm/string?endpointId=$ENDPOINT_ID" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"Name\": \"$STACK_NAME\",
    \"SwarmID\": \"$SWARM_ID\",
    \"StackFileContent\": $STACK_JSON,
    \"FromAppTemplate\": false
  }")

STATUS=$(echo "$RESPONSE" | sed -n 's/.*HTTP_STATUS://p')

if [[ "$STATUS" == "200" || "$STATUS" == "201" ]]; then
  log_ok "Stack $STACK_NAME criada"
else
  BODY=$(echo "$RESPONSE" | sed -n '1,/HTTP_STATUS:/p' | sed '$d')
  log_error "Falha ao criar stack (HTTP $STATUS)"
  echo "$BODY" | jq '.' 2>/dev/null || echo "$BODY"
  die "Deploy da stack falhou"
fi

log_info "Aguardando init do database (15s)..."
sleep 15

# ─── ETAPA 3: Executar SQLs via docker exec ────────────────────────────────
log_step "ETAPA 3/4: Executando scripts SQL"

PG_CONTAINER="$(docker ps --format '{{.Names}}' | grep -iE '(postgres)' | grep -iv 'init' | head -n1 || true)"
[[ -z "$PG_CONTAINER" ]] && die "Container PostgreSQL não encontrado"

log_ok "Container: $PG_CONTAINER"

# Ler a senha do Postgres da stack (ou usar a padrão)
PG_PASS="3acDZwaNJwPcpozU"

for sql_file in "$SQL_DIR/01_ddl.sql" "$SQL_DIR/02_dados.sql" "$SQL_DIR/03_funcoes_views.sql"; do
  fname=$(basename "$sql_file")
  log_info "Executando $fname..."
  
  OUTPUT=$(docker exec -i -e PGPASSWORD="$PG_PASS" "$PG_CONTAINER" \
    psql -U postgres -d agente_comercial --set ON_ERROR_STOP=on 2>&1 < "$sql_file")
  
  if [[ $? -ne 0 ]]; then
    echo "$OUTPUT"
    die "Falha ao executar $fname"
  fi
  
  log_ok "$fname executado"
done

# ─── ETAPA 4: Verificação e credenciais ────────────────────────────────────
log_step "ETAPA 4/4: Verificação final"

COUNTS=$(docker exec -e PGPASSWORD="$PG_PASS" "$PG_CONTAINER" \
  psql -U postgres -d agente_comercial -t -c "
  SELECT 
    (SELECT COUNT(*) FROM provedores) || ' provedores, ' ||
    (SELECT COUNT(*) FROM planos) || ' planos, ' ||
    (SELECT COUNT(*) FROM leads) || ' leads, ' ||
    (SELECT COUNT(*) FROM mensagens) || ' mensagens';
  " 2>&1)

# Salvar credenciais
CRED_DIR="/etc/agente-comercial"
CRED_FILE="$CRED_DIR/.credentials"
mkdir -p "$CRED_DIR"

APIKEYS=$(docker exec -e PGPASSWORD="$PG_PASS" "$PG_CONTAINER" \
  psql -U postgres -d agente_comercial -t -c "SELECT nome_provedor || '=' || apikey FROM provedores ORDER BY id;" 2>&1 | grep '=' || true)

cat > "$CRED_FILE" << EOF
#==============================================================================
# AGENTE COMERCIAL ISP - Credenciais
# Gerado em: $(date '+%F %T')
#==============================================================================
PG_HOST=postgres
PG_PORT=5432
PG_DATABASE=agente_comercial
PG_USER=agente_comercial
PG_PASSWORD=$PG_PASS
DATABASE_URL=postgresql://agente_comercial:${PG_PASS}@postgres:5432/agente_comercial

# APIKeys dos Provedores
$APIKEYS
EOF

chmod 600 "$CRED_FILE"

echo -e "${GREEN}"
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║              DEPLOY CONCLUÍDO COM SUCESSO                    ║"
echo "╠══════════════════════════════════════════════════════════════╣"
echo "║  Registros: $(echo $COUNTS | xargs)"
echo "║  Credenciais: $CRED_FILE"
echo "║                                                              ║"
echo "║  Para ver credenciais: cat $CRED_FILE"
echo "╚══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"
