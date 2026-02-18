#!/usr/bin/env bash
#==============================================================================
# AGENTE COMERCIAL ISP - Deploy Automatizado do Banco de Dados
#==============================================================================
# Executa na VPS conectando ao PostgreSQL via Docker (Swarm)
# Compatível com a infraestrutura br10ia_versaofinal_auto
#
# Uso:
#   sudo bash deploy-database.sh
#   sudo bash deploy-database.sh --senha MinhaS3nha
#   sudo bash deploy-database.sh --reset
#
# O script:
#   1. Detecta o container PostgreSQL automaticamente
#   2. Cria o database 'agente_comercial' (se não existir)
#   3. Cria user dedicado com senha segura (gerada ou fornecida)
#   4. Executa DDL (tabelas, índices, FKs, triggers)
#   5. Popula com dados realistas
#   6. Cria funções e views utilitárias
#   7. Salva todas as credenciais em /etc/agente-comercial/.credentials
#==============================================================================
set -euo pipefail

# ─── CORES ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ─── CONFIGURAÇÕES ──────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SQL_DIR="$SCRIPT_DIR/../sql"
CREDENTIALS_DIR="/etc/agente-comercial"
CREDENTIALS_FILE="$CREDENTIALS_DIR/.credentials"
LOG_FILE="/var/log/agente-comercial-deploy.log"

# Database
DB_NAME="agente_comercial"
DB_USER="agente_comercial"
DB_ENCODING="UTF8"

# PostgreSQL (detectado automaticamente)
PG_SERVICE_NAME="Postgres_postgres"
PG_ADMIN_USER="postgres"

# ─── FUNÇÕES AUXILIARES ─────────────────────────────────────────────────────
log()         { echo "[$(date '+%F %T')] $*" | tee -a "$LOG_FILE"; }
log_info()    { echo -e "${BLUE}[INFO]${NC}  $1"; log "[INFO] $1"; }
log_ok()      { echo -e "${GREEN}[OK]${NC}    $1"; log "[OK] $1"; }
log_warn()    { echo -e "${YELLOW}[AVISO]${NC} $1"; log "[AVISO] $1"; }
log_error()   { echo -e "${RED}[ERRO]${NC}  $1"; log "[ERRO] $1"; }
log_step()    { echo -e "\n${CYAN}${BOLD}═══ $1 ═══${NC}"; log "═══ $1 ═══"; }
die()         { log_error "$1"; exit 1; }

show_banner() {
  echo -e "${BLUE}"
  echo "╔══════════════════════════════════════════════════════════════╗"
  echo "║                                                              ║"
  echo "║   AGENTE COMERCIAL ISP - Deploy do Banco de Dados           ║"
  echo "║   Br10 Consultoria                                          ║"
  echo "║                                                              ║"
  echo "╚══════════════════════════════════════════════════════════════╝"
  echo -e "${NC}"
}

usage() {
  echo "Uso: sudo bash $0 [OPÇÕES]"
  echo ""
  echo "Opções:"
  echo "  --senha SENHA       Define a senha do user agente_comercial (padrão: gera aleatória)"
  echo "  --pg-senha SENHA    Senha do user postgres (padrão: lê de /etc/agente-comercial/.credentials ou pergunta)"
  echo "  --reset             Remove e recria o database do zero"
  echo "  --apenas-dados      Apenas repopula os dados (não recria tabelas)"
  echo "  --container NOME    Nome do container PostgreSQL (padrão: detecta automaticamente)"
  echo "  --help              Exibe esta ajuda"
  echo ""
  exit 0
}

gerar_senha() {
  openssl rand -base64 32 | tr -d '/+=' | head -c 32
}

# ─── PARSE ARGUMENTOS ──────────────────────────────────────────────────────
RESET_MODE=false
APENAS_DADOS=false
CUSTOM_SENHA=""
CUSTOM_PG_SENHA=""
CUSTOM_CONTAINER=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --senha)       CUSTOM_SENHA="$2"; shift 2 ;;
    --pg-senha)    CUSTOM_PG_SENHA="$2"; shift 2 ;;
    --reset)       RESET_MODE=true; shift ;;
    --apenas-dados) APENAS_DADOS=true; shift ;;
    --container)   CUSTOM_CONTAINER="$2"; shift 2 ;;
    --help)        usage ;;
    *)             die "Argumento desconhecido: $1. Use --help para ajuda." ;;
  esac
done

# ─── VERIFICAÇÕES ───────────────────────────────────────────────────────────
[ "$EUID" -ne 0 ] && die "Execute como root: sudo bash $0"
command -v docker >/dev/null 2>&1 || die "Docker não encontrado. Instale o Docker primeiro."

show_banner

mkdir -p "$CREDENTIALS_DIR"
chmod 700 "$CREDENTIALS_DIR"
touch "$LOG_FILE"

# ─── ETAPA 1: DETECTAR CONTAINER POSTGRESQL ────────────────────────────────
log_step "ETAPA 1/7: Detectando container PostgreSQL"

if [[ -n "$CUSTOM_CONTAINER" ]]; then
  PG_CONTAINER="$CUSTOM_CONTAINER"
  log_info "Usando container informado: $PG_CONTAINER"
else
  PG_CONTAINER="$(docker ps --format '{{.Names}}' | grep -iE '(postgres)' | grep -iv 'init' | head -n1 || true)"
fi

if [[ -z "$PG_CONTAINER" ]]; then
  die "Container PostgreSQL não encontrado. Verifique se o Postgres está rodando (docker ps)."
fi

log_ok "Container detectado: $PG_CONTAINER"

# Testar conectividade
docker exec "$PG_CONTAINER" pg_isready -U "$PG_ADMIN_USER" >/dev/null 2>&1 \
  || die "PostgreSQL não está respondendo no container $PG_CONTAINER"
log_ok "PostgreSQL respondendo"

# ─── ETAPA 2: CONFIGURAR CREDENCIAIS ───────────────────────────────────────
log_step "ETAPA 2/7: Configurando credenciais"

# Senha do postgres admin
if [[ -n "$CUSTOM_PG_SENHA" ]]; then
  PG_ADMIN_PASS="$CUSTOM_PG_SENHA"
  log_info "Usando senha postgres fornecida via --pg-senha"
elif [[ -f "$CREDENTIALS_FILE" ]]; then
  # Tenta ler do arquivo de credenciais anterior
  SAVED_PG_PASS="$(grep '^PG_ADMIN_PASS=' "$CREDENTIALS_FILE" 2>/dev/null | cut -d'=' -f2- || true)"
  if [[ -n "$SAVED_PG_PASS" ]]; then
    PG_ADMIN_PASS="$SAVED_PG_PASS"
    log_info "Senha postgres carregada de $CREDENTIALS_FILE"
  fi
fi

# Se ainda não tem a senha, tenta sem senha (trust local no container)
if [[ -z "${PG_ADMIN_PASS:-}" ]]; then
  # Testa se consegue conectar sem senha (auth-local=trust)
  if docker exec "$PG_CONTAINER" psql -U "$PG_ADMIN_USER" -c "SELECT 1" >/dev/null 2>&1; then
    PG_ADMIN_PASS=""
    log_info "Conexão local sem senha (trust) - OK"
  else
    die "Não foi possível conectar ao PostgreSQL. Use --pg-senha para informar a senha."
  fi
fi

# Senha do user agente_comercial
if [[ -n "$CUSTOM_SENHA" ]]; then
  DB_PASS="$CUSTOM_SENHA"
  log_info "Usando senha fornecida via --senha"
else
  DB_PASS="$(gerar_senha)"
  log_info "Senha gerada automaticamente para user '$DB_USER'"
fi

log_ok "Credenciais configuradas"

# ─── HELPER: EXECUTAR SQL ──────────────────────────────────────────────────
run_sql() {
  local db="${1:-postgres}"
  local sql="$2"
  if [[ -n "${PG_ADMIN_PASS:-}" ]]; then
    docker exec -e PGPASSWORD="$PG_ADMIN_PASS" "$PG_CONTAINER" \
      psql -U "$PG_ADMIN_USER" -d "$db" -c "$sql" 2>&1
  else
    docker exec "$PG_CONTAINER" \
      psql -U "$PG_ADMIN_USER" -d "$db" -c "$sql" 2>&1
  fi
}

run_sql_file() {
  local db="$1"
  local file="$2"
  if [[ -n "${PG_ADMIN_PASS:-}" ]]; then
    docker exec -i -e PGPASSWORD="$PG_ADMIN_PASS" "$PG_CONTAINER" \
      psql -U "$PG_ADMIN_USER" -d "$db" --set ON_ERROR_STOP=on 2>&1 < "$file"
  else
    docker exec -i "$PG_CONTAINER" \
      psql -U "$PG_ADMIN_USER" -d "$db" --set ON_ERROR_STOP=on 2>&1 < "$file"
  fi
}

# ─── ETAPA 3: CRIAR DATABASE E USER ────────────────────────────────────────
log_step "ETAPA 3/7: Criando database e user"

if [[ "$RESET_MODE" == true ]]; then
  log_warn "MODO RESET: Removendo database existente..."
  # Desconectar sessões ativas
  run_sql "postgres" "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '$DB_NAME' AND pid <> pg_backend_pid();" >/dev/null 2>&1 || true
  run_sql "postgres" "DROP DATABASE IF EXISTS $DB_NAME;" || true
  run_sql "postgres" "DROP USER IF EXISTS $DB_USER;" || true
  log_ok "Database e user removidos"
fi

# Criar database se não existir
DB_EXISTS=$(run_sql "postgres" "SELECT 1 FROM pg_database WHERE datname = '$DB_NAME'" | grep -c "1" || true)
if [[ "$DB_EXISTS" -eq 0 ]]; then
  run_sql "postgres" "CREATE DATABASE $DB_NAME ENCODING '$DB_ENCODING' LC_COLLATE 'C.UTF-8' LC_CTYPE 'C.UTF-8' TEMPLATE template0;" \
    || die "Falha ao criar database $DB_NAME"
  log_ok "Database '$DB_NAME' criado"
else
  log_info "Database '$DB_NAME' já existe"
fi

# Criar user se não existir
USER_EXISTS=$(run_sql "postgres" "SELECT 1 FROM pg_roles WHERE rolname = '$DB_USER'" | grep -c "1" || true)
if [[ "$USER_EXISTS" -eq 0 ]]; then
  run_sql "postgres" "CREATE USER $DB_USER WITH PASSWORD '$DB_PASS';" \
    || die "Falha ao criar user $DB_USER"
  log_ok "User '$DB_USER' criado"
else
  # Atualiza a senha
  run_sql "postgres" "ALTER USER $DB_USER WITH PASSWORD '$DB_PASS';" \
    || die "Falha ao atualizar senha do user $DB_USER"
  log_info "User '$DB_USER' já existe - senha atualizada"
fi

# Conceder privilégios
run_sql "postgres" "GRANT ALL PRIVILEGES ON DATABASE $DB_NAME TO $DB_USER;" >/dev/null 2>&1
run_sql "$DB_NAME" "GRANT ALL ON SCHEMA public TO $DB_USER;" >/dev/null 2>&1
run_sql "$DB_NAME" "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO $DB_USER;" >/dev/null 2>&1
run_sql "$DB_NAME" "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO $DB_USER;" >/dev/null 2>&1
run_sql "$DB_NAME" "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON FUNCTIONS TO $DB_USER;" >/dev/null 2>&1
log_ok "Privilégios concedidos"

# Extensões
run_sql "$DB_NAME" "CREATE EXTENSION IF NOT EXISTS pgcrypto;" >/dev/null 2>&1
run_sql "$DB_NAME" "CREATE EXTENSION IF NOT EXISTS pg_stat_statements;" >/dev/null 2>&1
run_sql "$DB_NAME" "CREATE EXTENSION IF NOT EXISTS vector;" >/dev/null 2>&1 || true
log_ok "Extensões habilitadas"

# ─── ETAPA 4: EXECUTAR DDL ─────────────────────────────────────────────────
log_step "ETAPA 4/7: Criando estrutura (tabelas, índices, FKs)"

if [[ "$APENAS_DADOS" == true ]]; then
  log_info "Modo --apenas-dados: pulando DDL"
else
  SQL_DDL="$SQL_DIR/01_ddl.sql"
  [[ -f "$SQL_DDL" ]] || die "Arquivo SQL não encontrado: $SQL_DDL"
  
  OUTPUT=$(run_sql_file "$DB_NAME" "$SQL_DDL" 2>&1)
  if [[ $? -ne 0 ]]; then
    echo "$OUTPUT"
    die "Falha ao executar DDL"
  fi
  log_ok "Estrutura criada com sucesso"
fi

# ─── ETAPA 5: POPULAR DADOS ────────────────────────────────────────────────
log_step "ETAPA 5/7: Populando dados"

SQL_DADOS="$SQL_DIR/02_dados.sql"
[[ -f "$SQL_DADOS" ]] || die "Arquivo SQL não encontrado: $SQL_DADOS"

OUTPUT=$(run_sql_file "$DB_NAME" "$SQL_DADOS" 2>&1)
if [[ $? -ne 0 ]]; then
  echo "$OUTPUT"
  die "Falha ao popular dados"
fi
log_ok "Dados inseridos com sucesso"

# ─── ETAPA 6: FUNÇÕES E VIEWS ──────────────────────────────────────────────
log_step "ETAPA 6/7: Criando funções e views"

if [[ "$APENAS_DADOS" == true ]]; then
  log_info "Modo --apenas-dados: pulando funções/views"
else
  SQL_FUNCOES="$SQL_DIR/03_funcoes_views.sql"
  [[ -f "$SQL_FUNCOES" ]] || die "Arquivo SQL não encontrado: $SQL_FUNCOES"
  
  OUTPUT=$(run_sql_file "$DB_NAME" "$SQL_FUNCOES" 2>&1)
  if [[ $? -ne 0 ]]; then
    echo "$OUTPUT"
    die "Falha ao criar funções/views"
  fi
  log_ok "Funções e views criadas"
fi

# ─── ETAPA 7: SALVAR CREDENCIAIS ───────────────────────────────────────────
log_step "ETAPA 7/7: Salvando credenciais"

# Buscar apikeys geradas
APIKEYS=$(run_sql "$DB_NAME" "SELECT nome_provedor || '=' || apikey FROM provedores ORDER BY id;" 2>&1 | grep '=' | grep -v 'nome_provedor' || true)

cat > "$CREDENTIALS_FILE" << EOF
#==============================================================================
# AGENTE COMERCIAL ISP - Credenciais
# Gerado em: $(date '+%F %T')
# MANTENHA ESTE ARQUIVO SEGURO!
#==============================================================================

# ─── PostgreSQL ─────────────────────────────────────────────────────────────
PG_HOST=postgres
PG_PORT=5432
PG_DATABASE=$DB_NAME
PG_USER=$DB_USER
PG_PASSWORD=$DB_PASS
PG_ADMIN_USER=$PG_ADMIN_USER
PG_ADMIN_PASS=${PG_ADMIN_PASS:-}

# ─── Connection String (para N8N, Chatwoot, aplicações) ─────────────────────
DATABASE_URL=postgresql://$DB_USER:$DB_PASS@postgres:5432/$DB_NAME
DATABASE_URL_EXTERNAL=postgresql://$DB_USER:$DB_PASS@SEU_IP_VPS:5432/$DB_NAME

# ─── APIKeys dos Provedores (geradas automaticamente) ───────────────────────
$APIKEYS

# ─── Uso no N8N ─────────────────────────────────────────────────────────────
# No node "Postgres" do N8N, use:
#   Host: postgres
#   Port: 5432
#   Database: $DB_NAME
#   User: $DB_USER
#   Password: $DB_PASS
#   SSL: desabilitado (rede interna Docker)

# ─── Uso no Chatwoot (webhook) ──────────────────────────────────────────────
# Configure um webhook no Chatwoot apontando para o N8N
# O N8N consulta este banco para obter dados do lead e histórico
EOF

chmod 600 "$CREDENTIALS_FILE"
log_ok "Credenciais salvas em: $CREDENTIALS_FILE"

# ─── VERIFICAÇÃO FINAL ─────────────────────────────────────────────────────
log_step "VERIFICAÇÃO FINAL"

COUNTS=$(run_sql "$DB_NAME" "
SELECT 
  (SELECT COUNT(*) FROM provedores) as provedores,
  (SELECT COUNT(*) FROM planos) as planos,
  (SELECT COUNT(*) FROM leads) as leads,
  (SELECT COUNT(*) FROM mensagens) as mensagens;
" 2>&1)

echo -e "${GREEN}"
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                 DEPLOY CONCLUÍDO COM SUCESSO                ║"
echo "╠══════════════════════════════════════════════════════════════╣"
echo "║                                                              ║"
echo "║  Database:    $DB_NAME                              ║"
echo "║  User:        $DB_USER                              ║"
echo "║  Senha:       (salva em $CREDENTIALS_FILE)    ║"
echo "║                                                              ║"
echo "╠══════════════════════════════════════════════════════════════╣"
echo "║  Registros criados:                                          ║"
echo "$COUNTS" | grep -E '[0-9]' | head -1 | awk '{printf "║  Provedores: %-4s  Planos: %-4s  Leads: %-4s  Msgs: %-4s    ║\n", $1, $3, $5, $7}'
echo "║                                                              ║"
echo "╠══════════════════════════════════════════════════════════════╣"
echo "║  Credenciais: $CREDENTIALS_FILE    ║"
echo "║  Log:         $LOG_FILE          ║"
echo "║                                                              ║"
echo "║  Para ver as credenciais:                                    ║"
echo "║  cat $CREDENTIALS_FILE                     ║"
echo "║                                                              ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

log "Deploy finalizado com sucesso"
