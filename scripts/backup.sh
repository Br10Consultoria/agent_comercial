#!/usr/bin/env bash
#==============================================================================
# AGENTE COMERCIAL ISP - Backup do Banco de Dados
#==============================================================================
# Faz backup da base agente_comercial no PostgreSQL da VPS via Docker.
# Compatível com a infraestrutura br10ia_versaofinal_auto (Docker Swarm).
#
# Funcionalidades:
#   - Backup completo (schema + dados) com pg_dump
#   - Compressão gzip (reduz ~80% do tamanho)
#   - Rotação automática por dias de retenção
#   - Validação de integridade (tamanho mínimo)
#   - Notificação via Telegram (opcional)
#   - Log detalhado com timestamps
#   - Suporte a cron para agendamento automático
#
# Uso:
#   sudo bash backup.sh                    # Backup padrão
#   sudo bash backup.sh --dir /mnt/backup  # Diretório customizado
#   sudo bash backup.sh --retencao 30      # Manter 30 dias
#   sudo bash backup.sh --instalar-cron    # Instala cron diário 3h da manhã
#   sudo bash backup.sh --remover-cron     # Remove o agendamento
#   sudo bash backup.sh --listar           # Lista backups existentes
#   sudo bash backup.sh --help             # Exibe ajuda
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
SCRIPT_PATH="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
DB_NAME="agente_comercial"
PG_USER="postgres"
PG_PASS=""
BACKUP_DIR="/storage/backups/agente_comercial"
RETENTION_DAYS=7
MIN_SIZE_KB=5
LOG_FILE="/var/log/agente-comercial-backup.log"
CREDENTIALS_FILE="/etc/agente-comercial/.credentials"
CRON_SCHEDULE="0 3 * * *"

# Telegram (desabilitado por padrão)
TELEGRAM_ENABLED=false
TELEGRAM_BOT_TOKEN=""
TELEGRAM_CHAT_ID=""

# ─── FUNÇÕES AUXILIARES ─────────────────────────────────────────────────────
log()         { echo "[$(date '+%F %T')] $*" | tee -a "$LOG_FILE" 2>/dev/null; }
log_info()    { echo -e "${BLUE}[INFO]${NC}  $1"; log "[INFO] $1"; }
log_ok()      { echo -e "${GREEN}[OK]${NC}    $1"; log "[OK] $1"; }
log_warn()    { echo -e "${YELLOW}[AVISO]${NC} $1"; log "[AVISO] $1"; }
log_error()   { echo -e "${RED}[ERRO]${NC}  $1"; log "[ERRO] $1"; }
log_step()    { echo -e "\n${CYAN}${BOLD}═══ $1 ═══${NC}"; log "═══ $1 ═══"; }
die()         { log_error "$1"; exit 1; }

show_banner() {
  echo -e "${BLUE}"
  echo "╔══════════════════════════════════════════════════════════════╗"
  echo "║   AGENTE COMERCIAL ISP - Backup do Banco de Dados           ║"
  echo "║   Br10 Consultoria                                          ║"
  echo "╚══════════════════════════════════════════════════════════════╝"
  echo -e "${NC}"
}

usage() {
  echo "Uso: sudo bash $0 [OPÇÕES]"
  echo ""
  echo "Opções:"
  echo "  --dir CAMINHO        Diretório de destino (padrão: $BACKUP_DIR)"
  echo "  --retencao DIAS      Dias de retenção dos backups (padrão: $RETENTION_DAYS)"
  echo "  --pg-senha SENHA     Senha do PostgreSQL (padrão: lê de $CREDENTIALS_FILE)"
  echo "  --container NOME     Nome do container PostgreSQL (padrão: detecta automaticamente)"
  echo "  --telegram TOKEN ID  Habilita notificação Telegram (bot token + chat id)"
  echo "  --instalar-cron      Instala agendamento cron (diário às 3h)"
  echo "  --cron-hora HORA     Hora do cron em formato HH:MM (padrão: 03:00)"
  echo "  --remover-cron       Remove o agendamento cron"
  echo "  --listar             Lista backups existentes com tamanhos"
  echo "  --help               Exibe esta ajuda"
  echo ""
  echo "Exemplos:"
  echo "  sudo bash $0                                 # Backup padrão"
  echo "  sudo bash $0 --dir /mnt/backup --retencao 30 # Backup customizado"
  echo "  sudo bash $0 --instalar-cron --cron-hora 02:30"
  echo "  sudo bash $0 --telegram BOT_TOKEN CHAT_ID"
  echo ""
  exit 0
}

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

# ─── PARSE ARGUMENTOS ──────────────────────────────────────────────────────
CUSTOM_CONTAINER=""
MODO_LISTAR=false
MODO_INSTALAR_CRON=false
MODO_REMOVER_CRON=false
CRON_HORA="03:00"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dir)             BACKUP_DIR="$2"; shift 2 ;;
    --retencao)        RETENTION_DAYS="$2"; shift 2 ;;
    --pg-senha)        PG_PASS="$2"; shift 2 ;;
    --container)       CUSTOM_CONTAINER="$2"; shift 2 ;;
    --telegram)        TELEGRAM_ENABLED=true; TELEGRAM_BOT_TOKEN="$2"; TELEGRAM_CHAT_ID="$3"; shift 3 ;;
    --instalar-cron)   MODO_INSTALAR_CRON=true; shift ;;
    --cron-hora)       CRON_HORA="$2"; shift 2 ;;
    --remover-cron)    MODO_REMOVER_CRON=true; shift ;;
    --listar)          MODO_LISTAR=true; shift ;;
    --help)            usage ;;
    *)                 die "Argumento desconhecido: $1. Use --help para ajuda." ;;
  esac
done

# ─── MODO: INSTALAR CRON ───────────────────────────────────────────────────
if [[ "$MODO_INSTALAR_CRON" == true ]]; then
  [ "$EUID" -ne 0 ] && die "Execute como root: sudo bash $0 --instalar-cron"

  HORA=$(echo "$CRON_HORA" | cut -d: -f1)
  MINUTO=$(echo "$CRON_HORA" | cut -d: -f2)
  CRON_LINE="$MINUTO $HORA * * * /usr/bin/bash $SCRIPT_PATH >> $LOG_FILE 2>&1"
  CRON_MARKER="# agente-comercial-backup"

  # Remove entrada anterior se existir
  crontab -l 2>/dev/null | grep -v "$CRON_MARKER" | crontab - 2>/dev/null || true

  # Adiciona nova entrada
  (crontab -l 2>/dev/null; echo "$CRON_LINE $CRON_MARKER") | crontab -

  echo -e "${GREEN}[OK]${NC} Cron instalado: backup diário às ${CRON_HORA}"
  echo -e "     Linha: ${CRON_LINE}"
  echo -e "     Log:   ${LOG_FILE}"
  echo -e "     Para verificar: ${CYAN}crontab -l${NC}"
  exit 0
fi

# ─── MODO: REMOVER CRON ────────────────────────────────────────────────────
if [[ "$MODO_REMOVER_CRON" == true ]]; then
  [ "$EUID" -ne 0 ] && die "Execute como root: sudo bash $0 --remover-cron"

  CRON_MARKER="# agente-comercial-backup"
  crontab -l 2>/dev/null | grep -v "$CRON_MARKER" | crontab - 2>/dev/null || true

  echo -e "${GREEN}[OK]${NC} Agendamento cron removido."
  exit 0
fi

# ─── MODO: LISTAR BACKUPS ──────────────────────────────────────────────────
if [[ "$MODO_LISTAR" == true ]]; then
  if [[ ! -d "$BACKUP_DIR" ]]; then
    echo -e "${YELLOW}Nenhum backup encontrado em: $BACKUP_DIR${NC}"
    exit 0
  fi

  TOTAL=$(find "$BACKUP_DIR" -name "${DB_NAME}_*.sql.gz" -type f 2>/dev/null | wc -l)
  if [[ $TOTAL -eq 0 ]]; then
    echo -e "${YELLOW}Nenhum backup encontrado em: $BACKUP_DIR${NC}"
    exit 0
  fi

  echo -e "${CYAN}${BOLD}Backups de '$DB_NAME' em $BACKUP_DIR${NC}"
  echo -e "${CYAN}$(printf '─%.0s' {1..60})${NC}"
  printf "%-40s %10s %s\n" "ARQUIVO" "TAMANHO" "DATA"
  echo "$(printf '─%.0s' {1..60})"

  TOTAL_KB=0
  find "$BACKUP_DIR" -name "${DB_NAME}_*.sql.gz" -type f -printf '%T@ %p\n' 2>/dev/null \
    | sort -rn | while read -r ts filepath; do
    fname=$(basename "$filepath")
    size_kb=$(du -k "$filepath" | awk '{print $1}')
    size_fmt=$(formatar_tamanho "$size_kb")
    data=$(date -d "@${ts%.*}" '+%d/%m/%Y %H:%M')
    printf "%-40s %10s %s\n" "$fname" "$size_fmt" "$data"
  done

  TOTAL_KB=$(du -sk "$BACKUP_DIR" 2>/dev/null | awk '{print $1}')
  echo "$(printf '─%.0s' {1..60})"
  echo -e "Total: ${BOLD}$TOTAL backups${NC} | Espaço: ${BOLD}$(formatar_tamanho "$TOTAL_KB")${NC} | Retenção: ${BOLD}${RETENTION_DAYS} dias${NC}"
  exit 0
fi

# ─── VERIFICAÇÕES ───────────────────────────────────────────────────────────
[ "$EUID" -ne 0 ] && die "Execute como root: sudo bash $0"
command -v docker >/dev/null 2>&1 || die "Docker não encontrado."

show_banner
mkdir -p "$BACKUP_DIR"
touch "$LOG_FILE"

# ─── ETAPA 1: DETECTAR CONTAINER ───────────────────────────────────────────
log_step "ETAPA 1/5: Detectando container PostgreSQL"

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
log_step "ETAPA 2/5: Carregando credenciais"

if [[ -z "$PG_PASS" && -f "$CREDENTIALS_FILE" ]]; then
  PG_PASS="$(grep '^PG_PASSWORD=' "$CREDENTIALS_FILE" 2>/dev/null | cut -d'=' -f2- || true)"
  if [[ -z "$PG_PASS" ]]; then
    PG_PASS="$(grep '^PG_ADMIN_PASS=' "$CREDENTIALS_FILE" 2>/dev/null | cut -d'=' -f2- || true)"
  fi
fi

# Testa conexão
if [[ -n "$PG_PASS" ]]; then
  docker exec -e PGPASSWORD="$PG_PASS" "$PG_CONTAINER" \
    psql -U "$PG_USER" -d "$DB_NAME" -c "SELECT 1" >/dev/null 2>&1 \
    || die "Falha na conexão com database '$DB_NAME'. Verifique a senha."
  log_ok "Conexão com '$DB_NAME' validada"
else
  docker exec "$PG_CONTAINER" \
    psql -U "$PG_USER" -d "$DB_NAME" -c "SELECT 1" >/dev/null 2>&1 \
    || die "Falha na conexão. Use --pg-senha para informar a senha."
  log_ok "Conexão local (trust) validada"
fi

# ─── ETAPA 3: EXECUTAR BACKUP ──────────────────────────────────────────────
log_step "ETAPA 3/5: Executando backup"

TS="$(date '+%F_%H-%M-%S')"
BACKUP_FILE="${DB_NAME}_${TS}.sql.gz"
BACKUP_PATH="$BACKUP_DIR/$BACKUP_FILE"
TMP_PATH="$BACKUP_PATH.tmp"

log_info "Destino: $BACKUP_PATH"

# Contagem de registros antes do backup (para validação)
COUNTS=""
if [[ -n "$PG_PASS" ]]; then
  COUNTS=$(docker exec -e PGPASSWORD="$PG_PASS" "$PG_CONTAINER" \
    psql -U "$PG_USER" -d "$DB_NAME" -t -c "
    SELECT json_build_object(
      'provedores', (SELECT COUNT(*) FROM provedores),
      'planos',     (SELECT COUNT(*) FROM planos),
      'leads',      (SELECT COUNT(*) FROM leads),
      'mensagens',  (SELECT COUNT(*) FROM mensagens)
    );" 2>/dev/null | xargs || true)
fi

# pg_dump com compressão gzip
INICIO=$(date +%s)

if [[ -n "$PG_PASS" ]]; then
  docker exec -e PGPASSWORD="$PG_PASS" "$PG_CONTAINER" \
    pg_dump -U "$PG_USER" \
      --format=p \
      --no-owner \
      --no-privileges \
      --verbose \
      --encoding=UTF8 \
      "$DB_NAME" 2>>"$LOG_FILE" \
    | gzip -9 > "$TMP_PATH"
else
  docker exec "$PG_CONTAINER" \
    pg_dump -U "$PG_USER" \
      --format=p \
      --no-owner \
      --no-privileges \
      --verbose \
      --encoding=UTF8 \
      "$DB_NAME" 2>>"$LOG_FILE" \
    | gzip -9 > "$TMP_PATH"
fi

FIM=$(date +%s)
DURACAO=$((FIM - INICIO))

# Validação de integridade
[[ -s "$TMP_PATH" ]] || die "Backup gerou arquivo vazio!"

SIZE_KB=$(du -k "$TMP_PATH" | awk '{print $1}')
if [[ $SIZE_KB -lt $MIN_SIZE_KB ]]; then
  rm -f "$TMP_PATH"
  die "Backup muito pequeno (${SIZE_KB}KB < ${MIN_SIZE_KB}KB). Possível falha no pg_dump."
fi

# Testa integridade do gzip
gzip -t "$TMP_PATH" 2>/dev/null || die "Arquivo gzip corrompido!"

mv "$TMP_PATH" "$BACKUP_PATH"
chmod 640 "$BACKUP_PATH"

log_ok "Backup concluído: $BACKUP_FILE ($(formatar_tamanho $SIZE_KB)) em ${DURACAO}s"

# ─── ETAPA 4: ROTAÇÃO (RETENÇÃO) ───────────────────────────────────────────
log_step "ETAPA 4/5: Rotação de backups antigos"

ANTES=$(find "$BACKUP_DIR" -name "${DB_NAME}_*.sql.gz" -type f | wc -l)

REMOVIDOS=$(find "$BACKUP_DIR" -name "${DB_NAME}_*.sql.gz" -type f -mtime +"$RETENTION_DAYS" -print -delete 2>/dev/null | wc -l)

DEPOIS=$(find "$BACKUP_DIR" -name "${DB_NAME}_*.sql.gz" -type f | wc -l)

if [[ $REMOVIDOS -gt 0 ]]; then
  log_ok "Removidos $REMOVIDOS backups com mais de ${RETENTION_DAYS} dias"
else
  log_info "Nenhum backup expirado para remover"
fi

log_info "Backups mantidos: $DEPOIS"

# ─── ETAPA 5: NOTIFICAÇÃO TELEGRAM ─────────────────────────────────────────
log_step "ETAPA 5/5: Notificação"

RESUMO="Backup agente_comercial concluído
Arquivo: $BACKUP_FILE
Tamanho: $(formatar_tamanho $SIZE_KB)
Duração: ${DURACAO}s
Registros: $COUNTS
Backups mantidos: $DEPOIS (retenção: ${RETENTION_DAYS}d)"

if [[ "$TELEGRAM_ENABLED" == true && -n "$TELEGRAM_BOT_TOKEN" && -n "$TELEGRAM_CHAT_ID" ]]; then
  log_info "Enviando notificação via Telegram..."

  # Envia mensagem de texto
  curl -sS -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    -d "chat_id=$TELEGRAM_CHAT_ID" \
    -d "text=$RESUMO" \
    -d "parse_mode=Markdown" >/dev/null 2>&1 || log_warn "Falha ao enviar mensagem Telegram"

  # Envia o arquivo se for menor que 50MB
  if [[ $SIZE_KB -lt 51200 ]]; then
    curl -sS -F "chat_id=$TELEGRAM_CHAT_ID" \
      -F "document=@${BACKUP_PATH}" \
      -F "caption=Backup ${DB_NAME} - $(date '+%d/%m/%Y %H:%M')" \
      "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendDocument" >/dev/null 2>&1 \
      || log_warn "Falha ao enviar arquivo Telegram"
    log_ok "Backup enviado para Telegram"
  else
    log_warn "Arquivo muito grande para Telegram (>50MB). Apenas notificação enviada."
  fi
else
  log_info "Telegram desabilitado. Use --telegram BOT_TOKEN CHAT_ID para habilitar."
fi

# ─── RESUMO FINAL ──────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║              BACKUP CONCLUÍDO COM SUCESSO                    ║${NC}"
echo -e "${GREEN}╠══════════════════════════════════════════════════════════════╣${NC}"
echo -e "${GREEN}║${NC}  Arquivo:   ${BOLD}$BACKUP_FILE${NC}"
echo -e "${GREEN}║${NC}  Tamanho:   ${BOLD}$(formatar_tamanho $SIZE_KB)${NC}"
echo -e "${GREEN}║${NC}  Duração:   ${BOLD}${DURACAO}s${NC}"
echo -e "${GREEN}║${NC}  Registros: ${BOLD}$COUNTS${NC}"
echo -e "${GREEN}║${NC}  Caminho:   ${BOLD}$BACKUP_PATH${NC}"
echo -e "${GREEN}║${NC}  Mantidos:  ${BOLD}$DEPOIS backups${NC} (retenção: ${RETENTION_DAYS} dias)"
echo -e "${GREEN}║${NC}  Log:       ${BOLD}$LOG_FILE${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

log "Backup finalizado com sucesso: $BACKUP_FILE ($(formatar_tamanho $SIZE_KB))"
