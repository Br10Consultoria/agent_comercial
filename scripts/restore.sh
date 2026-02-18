#!/usr/bin/env bash
#==============================================================================
# AGENTE COMERCIAL ISP - Restauração do Banco de Dados
#==============================================================================
# Restaura a base agente_comercial a partir de um backup .sql.gz
# Compatível com a infraestrutura br10ia_versaofinal_auto (Docker Swarm).
#
# Funcionalidades:
#   - Restauração completa a partir de backup .sql.gz
#   - Backup automático antes de restaurar (safety net)
#   - Modo interativo: lista backups e permite escolher
#   - Modo direto: restaura arquivo específico
#   - Validação de integridade do arquivo antes de restaurar
#   - Verificação pós-restauração (contagem de registros)
#   - Log detalhado de todas as operações
#
# Uso:
#   sudo bash restore.sh                                  # Modo interativo
#   sudo bash restore.sh --arquivo /caminho/backup.sql.gz # Modo direto
#   sudo bash restore.sh --ultimo                         # Restaura o mais recente
#   sudo bash restore.sh --sem-backup-previo              # Pula backup de segurança
#   sudo bash restore.sh --help                           # Exibe ajuda
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

# ─── CONFIGURAÇÕES PADRÃO ──────────────────────────────────────────────────
DB_NAME="agente_comercial"
PG_USER="postgres"
PG_PASS=""
BACKUP_DIR="/storage/backups/agente_comercial"
LOG_FILE="/var/log/agente-comercial-restore.log"
CREDENTIALS_FILE="/etc/agente-comercial/.credentials"

# ─── FUNÇÕES AUXILIARES ─────────────────────────────────────────────────────
log()         { echo "[$(date '+%F %T')] $*" | tee -a "$LOG_FILE" 2>/dev/null; }
log_info()    { echo -e "${BLUE}[INFO]${NC}  $1"; log "[INFO] $1"; }
log_ok()      { echo -e "${GREEN}[OK]${NC}    $1"; log "[OK] $1"; }
log_warn()    { echo -e "${YELLOW}[AVISO]${NC} $1"; log "[AVISO] $1"; }
log_error()   { echo -e "${RED}[ERRO]${NC}  $1"; log "[ERRO] $1"; }
log_step()    { echo -e "\n${CYAN}${BOLD}═══ $1 ═══${NC}"; log "═══ $1 ═══"; }
die()         { log_error "$1"; exit 1; }

formatar_tamanho() {
  local kb=$1
  if [[ $kb -ge 1048576 ]]; then
    echo "$(echo "scale=1; $kb/1048576" | bc)GB"
  elif [[ $kb -ge 1024 ]]; then
    echo "$(echo "scale=1; $kb/1024" | bc)MB"
  else
    echo "${kb}KB"
  fi
}

show_banner() {
  echo -e "${YELLOW}"
  echo "╔══════════════════════════════════════════════════════════════╗"
  echo "║   AGENTE COMERCIAL ISP - Restauração do Banco de Dados      ║"
  echo "║   Br10 Consultoria                                          ║"
  echo "╚══════════════════════════════════════════════════════════════╝"
  echo -e "${NC}"
}

usage() {
  echo "Uso: sudo bash $0 [OPÇÕES]"
  echo ""
  echo "Opções:"
  echo "  --arquivo CAMINHO    Restaura de um arquivo .sql.gz específico"
  echo "  --ultimo             Restaura automaticamente o backup mais recente"
  echo "  --dir CAMINHO        Diretório onde estão os backups (padrão: $BACKUP_DIR)"
  echo "  --pg-senha SENHA     Senha do PostgreSQL"
  echo "  --container NOME     Nome do container PostgreSQL"
  echo "  --sem-backup-previo  Não faz backup de segurança antes de restaurar"
  echo "  --force              Pula confirmação (para uso em scripts)"
  echo "  --help               Exibe esta ajuda"
  echo ""
  echo "Exemplos:"
  echo "  sudo bash $0                                              # Interativo"
  echo "  sudo bash $0 --ultimo                                     # Mais recente"
  echo "  sudo bash $0 --arquivo /storage/backups/agente_comercial/agente_comercial_2026-02-18_03-00-00.sql.gz"
  echo "  sudo bash $0 --ultimo --sem-backup-previo --force         # Automático"
  echo ""
  exit 0
}

run_sql() {
  local db="$1"
  local sql="$2"
  if [[ -n "$PG_PASS" ]]; then
    docker exec -e PGPASSWORD="$PG_PASS" "$PG_CONTAINER" \
      psql -U "$PG_USER" -d "$db" -t -c "$sql" 2>/dev/null | xargs
  else
    docker exec "$PG_CONTAINER" \
      psql -U "$PG_USER" -d "$db" -t -c "$sql" 2>/dev/null | xargs
  fi
}

contar_registros() {
  run_sql "$DB_NAME" "
    SELECT json_build_object(
      'provedores', (SELECT COUNT(*) FROM provedores),
      'planos',     (SELECT COUNT(*) FROM planos),
      'leads',      (SELECT COUNT(*) FROM leads),
      'mensagens',  (SELECT COUNT(*) FROM mensagens)
    );" 2>/dev/null || echo "{}"
}

# ─── PARSE ARGUMENTOS ──────────────────────────────────────────────────────
ARQUIVO=""
MODO_ULTIMO=false
FAZER_BACKUP_PREVIO=true
FORCE=false
CUSTOM_CONTAINER=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --arquivo)           ARQUIVO="$2"; shift 2 ;;
    --ultimo)            MODO_ULTIMO=true; shift ;;
    --dir)               BACKUP_DIR="$2"; shift 2 ;;
    --pg-senha)          PG_PASS="$2"; shift 2 ;;
    --container)         CUSTOM_CONTAINER="$2"; shift 2 ;;
    --sem-backup-previo) FAZER_BACKUP_PREVIO=false; shift ;;
    --force)             FORCE=true; shift ;;
    --help)              usage ;;
    *)                   die "Argumento desconhecido: $1. Use --help para ajuda." ;;
  esac
done

# ─── VERIFICAÇÕES ───────────────────────────────────────────────────────────
[ "$EUID" -ne 0 ] && die "Execute como root: sudo bash $0"
command -v docker >/dev/null 2>&1 || die "Docker não encontrado."

show_banner
touch "$LOG_FILE"

# ─── ETAPA 1: DETECTAR CONTAINER ───────────────────────────────────────────
log_step "ETAPA 1/6: Detectando container PostgreSQL"

if [[ -n "$CUSTOM_CONTAINER" ]]; then
  PG_CONTAINER="$CUSTOM_CONTAINER"
else
  PG_CONTAINER="$(docker ps --format '{{.Names}}' | grep -iE '(postgres)' | grep -iv 'init' | head -n1 || true)"
fi

[[ -z "$PG_CONTAINER" ]] && die "Container PostgreSQL não encontrado. Use --container NOME."

docker exec "$PG_CONTAINER" pg_isready -U "$PG_USER" >/dev/null 2>&1 \
  || die "PostgreSQL não está respondendo no container $PG_CONTAINER"

log_ok "Container: $PG_CONTAINER"

# ─── ETAPA 2: CARREGAR CREDENCIAIS ─────────────────────────────────────────
log_step "ETAPA 2/6: Carregando credenciais"

if [[ -z "$PG_PASS" && -f "$CREDENTIALS_FILE" ]]; then
  PG_PASS="$(grep '^PG_PASSWORD=' "$CREDENTIALS_FILE" 2>/dev/null | cut -d'=' -f2- || true)"
  if [[ -z "$PG_PASS" ]]; then
    PG_PASS="$(grep '^PG_ADMIN_PASS=' "$CREDENTIALS_FILE" 2>/dev/null | cut -d'=' -f2- || true)"
  fi
fi

# Testa conexão ao database
DB_EXISTS=$(run_sql "postgres" "SELECT 1 FROM pg_database WHERE datname = '$DB_NAME'" 2>/dev/null || true)

if [[ "$DB_EXISTS" == *"1"* ]]; then
  log_ok "Database '$DB_NAME' encontrado"
else
  log_warn "Database '$DB_NAME' não existe. Será criado durante a restauração."
fi

# ─── ETAPA 3: SELECIONAR ARQUIVO DE BACKUP ─────────────────────────────────
log_step "ETAPA 3/6: Selecionando backup para restauração"

if [[ -n "$ARQUIVO" ]]; then
  # Modo direto: arquivo fornecido
  [[ -f "$ARQUIVO" ]] || die "Arquivo não encontrado: $ARQUIVO"
  RESTORE_FILE="$ARQUIVO"
  log_info "Arquivo selecionado: $RESTORE_FILE"

elif [[ "$MODO_ULTIMO" == true ]]; then
  # Modo automático: mais recente
  RESTORE_FILE=$(find "$BACKUP_DIR" -name "${DB_NAME}_*.sql.gz" -type f -printf '%T@ %p\n' 2>/dev/null \
    | sort -rn | head -1 | awk '{print $2}')
  [[ -n "$RESTORE_FILE" ]] || die "Nenhum backup encontrado em $BACKUP_DIR"
  log_info "Backup mais recente: $(basename "$RESTORE_FILE")"

else
  # Modo interativo: listar e escolher
  BACKUPS=()
  while IFS= read -r line; do
    BACKUPS+=("$line")
  done < <(find "$BACKUP_DIR" -name "${DB_NAME}_*.sql.gz" -type f -printf '%T@ %p\n' 2>/dev/null | sort -rn | awk '{print $2}')

  if [[ ${#BACKUPS[@]} -eq 0 ]]; then
    die "Nenhum backup encontrado em $BACKUP_DIR. Use --arquivo para informar o caminho."
  fi

  echo ""
  echo -e "${CYAN}Backups disponíveis:${NC}"
  echo "$(printf '─%.0s' {1..65})"
  printf "  %-3s %-45s %10s\n" "#" "ARQUIVO" "TAMANHO"
  echo "$(printf '─%.0s' {1..65})"

  for i in "${!BACKUPS[@]}"; do
    fname=$(basename "${BACKUPS[$i]}")
    size_kb=$(du -k "${BACKUPS[$i]}" | awk '{print $1}')
    printf "  %-3s %-45s %10s\n" "$((i+1))" "$fname" "$(formatar_tamanho $size_kb)"
  done

  echo "$(printf '─%.0s' {1..65})"
  echo ""

  while true; do
    read -rp "Escolha o número do backup (1-${#BACKUPS[@]}): " ESCOLHA
    if [[ "$ESCOLHA" =~ ^[0-9]+$ ]] && [[ $ESCOLHA -ge 1 ]] && [[ $ESCOLHA -le ${#BACKUPS[@]} ]]; then
      RESTORE_FILE="${BACKUPS[$((ESCOLHA-1))]}"
      break
    fi
    echo -e "${RED}Opção inválida. Tente novamente.${NC}"
  done

  log_info "Selecionado: $(basename "$RESTORE_FILE")"
fi

# Validar integridade do arquivo
log_info "Validando integridade do arquivo..."
gzip -t "$RESTORE_FILE" 2>/dev/null || die "Arquivo gzip corrompido: $RESTORE_FILE"

SIZE_KB=$(du -k "$RESTORE_FILE" | awk '{print $1}')
log_ok "Arquivo válido: $(basename "$RESTORE_FILE") ($(formatar_tamanho $SIZE_KB))"

# ─── CONFIRMAÇÃO ────────────────────────────────────────────────────────────
if [[ "$FORCE" != true ]]; then
  echo ""
  echo -e "${YELLOW}${BOLD}ATENÇÃO: Esta operação irá SUBSTITUIR todos os dados atuais${NC}"
  echo -e "${YELLOW}do database '${DB_NAME}' pelo conteúdo do backup selecionado.${NC}"
  echo ""

  if [[ "$DB_EXISTS" == *"1"* ]]; then
    COUNTS_ANTES=$(contar_registros)
    echo -e "  Dados atuais: ${BOLD}$COUNTS_ANTES${NC}"
  fi
  echo -e "  Backup:       ${BOLD}$(basename "$RESTORE_FILE")${NC}"
  echo ""

  read -rp "Deseja continuar? (s/N): " CONFIRMA
  [[ "$CONFIRMA" =~ ^[Ss]$ ]] || { echo "Cancelado."; exit 0; }
fi

# ─── ETAPA 4: BACKUP DE SEGURANÇA ──────────────────────────────────────────
log_step "ETAPA 4/6: Backup de segurança (pré-restauração)"

if [[ "$FAZER_BACKUP_PREVIO" == true && "$DB_EXISTS" == *"1"* ]]; then
  SAFETY_DIR="$BACKUP_DIR/pre-restore"
  mkdir -p "$SAFETY_DIR"

  SAFETY_FILE="$SAFETY_DIR/${DB_NAME}_pre-restore_$(date '+%F_%H-%M-%S').sql.gz"

  log_info "Criando backup de segurança..."

  if [[ -n "$PG_PASS" ]]; then
    docker exec -e PGPASSWORD="$PG_PASS" "$PG_CONTAINER" \
      pg_dump -U "$PG_USER" --format=p --no-owner --no-privileges "$DB_NAME" \
      | gzip -9 > "$SAFETY_FILE" 2>/dev/null
  else
    docker exec "$PG_CONTAINER" \
      pg_dump -U "$PG_USER" --format=p --no-owner --no-privileges "$DB_NAME" \
      | gzip -9 > "$SAFETY_FILE" 2>/dev/null
  fi

  if [[ -s "$SAFETY_FILE" ]]; then
    SAFETY_KB=$(du -k "$SAFETY_FILE" | awk '{print $1}')
    log_ok "Backup de segurança: $(basename "$SAFETY_FILE") ($(formatar_tamanho $SAFETY_KB))"
  else
    log_warn "Backup de segurança vazio (database pode estar vazio)"
    rm -f "$SAFETY_FILE"
  fi
else
  if [[ "$FAZER_BACKUP_PREVIO" == false ]]; then
    log_warn "Backup de segurança desabilitado (--sem-backup-previo)"
  else
    log_info "Database não existe ainda, backup de segurança desnecessário"
  fi
fi

# ─── ETAPA 5: RESTAURAÇÃO ──────────────────────────────────────────────────
log_step "ETAPA 5/6: Restaurando banco de dados"

INICIO=$(date +%s)

# Desconectar sessões ativas
if [[ "$DB_EXISTS" == *"1"* ]]; then
  log_info "Desconectando sessões ativas..."
  run_sql "postgres" "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '$DB_NAME' AND pid <> pg_backend_pid();" >/dev/null 2>&1 || true
  sleep 2
fi

# Dropar e recriar o database (restauração limpa)
log_info "Recriando database '$DB_NAME'..."

if [[ -n "$PG_PASS" ]]; then
  docker exec -e PGPASSWORD="$PG_PASS" "$PG_CONTAINER" \
    psql -U "$PG_USER" -d postgres -c "DROP DATABASE IF EXISTS $DB_NAME;" 2>/dev/null || true

  docker exec -e PGPASSWORD="$PG_PASS" "$PG_CONTAINER" \
    psql -U "$PG_USER" -d postgres -c "CREATE DATABASE $DB_NAME ENCODING 'UTF8' LC_COLLATE 'C.UTF-8' LC_CTYPE 'C.UTF-8' TEMPLATE template0;" 2>/dev/null \
    || docker exec -e PGPASSWORD="$PG_PASS" "$PG_CONTAINER" \
      psql -U "$PG_USER" -d postgres -c "CREATE DATABASE $DB_NAME ENCODING 'UTF8';" 2>/dev/null \
    || die "Falha ao criar database"

  # Extensões necessárias
  docker exec -e PGPASSWORD="$PG_PASS" "$PG_CONTAINER" \
    psql -U "$PG_USER" -d "$DB_NAME" -c "CREATE EXTENSION IF NOT EXISTS pgcrypto;" >/dev/null 2>&1
  docker exec -e PGPASSWORD="$PG_PASS" "$PG_CONTAINER" \
    psql -U "$PG_USER" -d "$DB_NAME" -c "CREATE EXTENSION IF NOT EXISTS vector;" >/dev/null 2>&1 || true
else
  docker exec "$PG_CONTAINER" \
    psql -U "$PG_USER" -d postgres -c "DROP DATABASE IF EXISTS $DB_NAME;" 2>/dev/null || true
  docker exec "$PG_CONTAINER" \
    psql -U "$PG_USER" -d postgres -c "CREATE DATABASE $DB_NAME ENCODING 'UTF8';" 2>/dev/null \
    || die "Falha ao criar database"
  docker exec "$PG_CONTAINER" \
    psql -U "$PG_USER" -d "$DB_NAME" -c "CREATE EXTENSION IF NOT EXISTS pgcrypto;" >/dev/null 2>&1
  docker exec "$PG_CONTAINER" \
    psql -U "$PG_USER" -d "$DB_NAME" -c "CREATE EXTENSION IF NOT EXISTS vector;" >/dev/null 2>&1 || true
fi

log_ok "Database recriado"

# Restaurar o dump
log_info "Aplicando dump SQL..."

if [[ -n "$PG_PASS" ]]; then
  gunzip -c "$RESTORE_FILE" | docker exec -i -e PGPASSWORD="$PG_PASS" "$PG_CONTAINER" \
    psql -U "$PG_USER" -d "$DB_NAME" --set ON_ERROR_STOP=off -q 2>>"$LOG_FILE"
else
  gunzip -c "$RESTORE_FILE" | docker exec -i "$PG_CONTAINER" \
    psql -U "$PG_USER" -d "$DB_NAME" --set ON_ERROR_STOP=off -q 2>>"$LOG_FILE"
fi

FIM=$(date +%s)
DURACAO=$((FIM - INICIO))

log_ok "Dump aplicado em ${DURACAO}s"

# Recriar permissões do user agente_comercial
log_info "Recriando permissões do user agente_comercial..."
run_sql "postgres" "GRANT ALL PRIVILEGES ON DATABASE $DB_NAME TO agente_comercial;" >/dev/null 2>&1 || true
run_sql "$DB_NAME" "GRANT ALL ON SCHEMA public TO agente_comercial;" >/dev/null 2>&1 || true
run_sql "$DB_NAME" "GRANT ALL ON ALL TABLES IN SCHEMA public TO agente_comercial;" >/dev/null 2>&1 || true
run_sql "$DB_NAME" "GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO agente_comercial;" >/dev/null 2>&1 || true
run_sql "$DB_NAME" "GRANT ALL ON ALL FUNCTIONS IN SCHEMA public TO agente_comercial;" >/dev/null 2>&1 || true
run_sql "$DB_NAME" "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO agente_comercial;" >/dev/null 2>&1 || true
run_sql "$DB_NAME" "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO agente_comercial;" >/dev/null 2>&1 || true
run_sql "$DB_NAME" "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON FUNCTIONS TO agente_comercial;" >/dev/null 2>&1 || true

log_ok "Permissões restauradas"

# ─── ETAPA 6: VERIFICAÇÃO PÓS-RESTAURAÇÃO ──────────────────────────────────
log_step "ETAPA 6/6: Verificação pós-restauração"

COUNTS_DEPOIS=$(contar_registros)

# Verificar se as tabelas existem
TABELAS=$(run_sql "$DB_NAME" "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public' AND table_type = 'BASE TABLE';" 2>/dev/null || echo "0")
FUNCOES=$(run_sql "$DB_NAME" "SELECT COUNT(*) FROM information_schema.routines WHERE routine_schema = 'public';" 2>/dev/null || echo "0")
VIEWS=$(run_sql "$DB_NAME" "SELECT COUNT(*) FROM information_schema.views WHERE table_schema = 'public';" 2>/dev/null || echo "0")

log_ok "Tabelas: $TABELAS | Funções: $FUNCOES | Views: $VIEWS"
log_ok "Registros: $COUNTS_DEPOIS"

# ─── RESUMO FINAL ──────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║           RESTAURAÇÃO CONCLUÍDA COM SUCESSO                  ║${NC}"
echo -e "${GREEN}╠══════════════════════════════════════════════════════════════╣${NC}"
echo -e "${GREEN}║${NC}  Backup:    ${BOLD}$(basename "$RESTORE_FILE")${NC}"
echo -e "${GREEN}║${NC}  Duração:   ${BOLD}${DURACAO}s${NC}"
echo -e "${GREEN}║${NC}  Tabelas:   ${BOLD}$TABELAS${NC}"
echo -e "${GREEN}║${NC}  Funções:   ${BOLD}$FUNCOES${NC}"
echo -e "${GREEN}║${NC}  Views:     ${BOLD}$VIEWS${NC}"
echo -e "${GREEN}║${NC}  Registros: ${BOLD}$COUNTS_DEPOIS${NC}"
if [[ "$FAZER_BACKUP_PREVIO" == true ]]; then
echo -e "${GREEN}║${NC}"
echo -e "${GREEN}║${NC}  Backup de segurança (rollback):"
echo -e "${GREEN}║${NC}  ${BOLD}$SAFETY_DIR/${NC}"
fi
echo -e "${GREEN}║${NC}"
echo -e "${GREEN}║${NC}  Log: ${BOLD}$LOG_FILE${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

log "Restauração finalizada: $(basename "$RESTORE_FILE") -> $DB_NAME (${DURACAO}s)"
