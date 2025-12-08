#!/bin/bash

# Monitoring script für Paradex Collection
# Zeigt Echtzeit-Fortschritt aller Worker und DB-Status

set -e

DB_PATH="./funding-data.db"

# Finde neuestes Log-Verzeichnis
LOG_DIR=$(find ./logs -maxdepth 1 -type d -name "paradex-recent-*" 2>/dev/null | sort -r | head -1)

if [ -z "$LOG_DIR" ]; then
  echo "No active collection found in ./logs/paradex-recent-*"
  echo "Start collection with: ./collect-paradex-recent.sh"
  exit 1
fi

# Farben
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

clear

echo -e "${CYAN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║         Paradex Historical Data Collection Monitor            ║${NC}"
echo -e "${CYAN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo ""

# Funktion: Zähle DB Records
count_db_records() {
  local table=$1
  sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM $table WHERE exchange = 'paradex';" 2>/dev/null || echo "0"
}

# Funktion: Letzte 5 Einträge anzeigen
show_recent_records() {
  echo -e "\n${CYAN}📊 Latest 5 Database Entries:${NC}"
  sqlite3 "$DB_PATH" "SELECT datetime(collected_at/1000, 'unixepoch') as time, trading_pair, printf('%.6f', funding_rate_percent) as rate_pct FROM unified_funding_rates WHERE exchange = 'paradex' ORDER BY collected_at DESC LIMIT 5;" 2>/dev/null | column -t -s '|' || echo "No data yet"
}

# Funktion: Worker Status aus Logs extrahieren
parse_worker_logs() {
  local worker_num=$1
  local log_file="$LOG_DIR/worker_${worker_num}.log"

  if [ ! -f "$log_file" ]; then
    echo -e "${YELLOW}Worker $worker_num: No log file${NC}"
    return
  fi

  # Letzte Zeile mit Fortschritt
  local last_line=$(grep -E "^\[.*%\]" "$log_file" 2>/dev/null | tail -1)

  if [ -z "$last_line" ]; then
    # Prüfe ob Worker fertig ist
    if grep -q "Worker.*completed" "$log_file" 2>/dev/null; then
      echo -e "${GREEN}Worker $worker_num: ✓ Completed${NC}"
    else
      echo -e "${YELLOW}Worker $worker_num: Starting...${NC}"
    fi
  else
    # Extrahiere Details
    local percent=$(echo "$last_line" | grep -oE '\[[0-9]+%\]' | tr -d '[]%')
    local current=$(echo "$last_line" | grep -oE '\([0-9]+/' | tr -d '(/')
    local total=$(echo "$last_line" | grep -oE '/[0-9]+\)' | tr -d '/)')
    local market=$(echo "$last_line" | awk '{print $3}')
    local status=$(echo "$last_line" | grep -oE '✓|✗')

    # Farbe basierend auf Status
    local color=$BLUE
    if [ "$status" = "✓" ]; then
      color=$GREEN
    elif [ "$status" = "✗" ]; then
      color=$RED
    fi

    # Fortschrittsbalken
    local bar_width=20
    local filled=$((percent * bar_width / 100))
    local empty=$((bar_width - filled))
    local bar=$(printf "█%.0s" $(seq 1 $filled))$(printf "░%.0s" $(seq 1 $empty))

    echo -e "${color}Worker $worker_num: [$bar] ${percent}% (${current}/${total}) $market${NC}"
  fi
}

# Hauptloop
while true; do
  # Cursor nach oben
  tput cup 5 0

  # DB Status
  unified_count=$(count_db_records "unified_funding_rates")
  hourly_count=$(count_db_records "paradex_hourly_averages")

  echo -e "${GREEN}📈 Database Status:${NC}"
  echo -e "   unified_funding_rates:     ${CYAN}${unified_count}${NC} records"
  echo -e "   paradex_hourly_averages:   ${CYAN}${hourly_count}${NC} records"
  echo ""

  # Worker Status
  echo -e "${GREEN}👷 Worker Status:${NC}"
  for i in {1..5}; do
    parse_worker_logs $i
  done
  echo ""

  # Letzte Aktivität
  echo -e "${GREEN}🕐 Last Activity:${NC}"
  for i in {1..5}; do
    log_file="$LOG_DIR/worker_${i}.log"
    if [ -f "$log_file" ]; then
      last_line=$(tail -1 "$log_file" 2>/dev/null)
      last_time=$(stat -f "%Sm" -t "%H:%M:%S" "$log_file" 2>/dev/null || stat -c "%y" "$log_file" 2>/dev/null | cut -d' ' -f2 | cut -d'.' -f1)
      echo -e "   Worker $i: ${last_time}"
    fi
  done

  # Zeige letzte DB Einträge
  show_recent_records

  echo ""
  echo -e "${YELLOW}Press Ctrl+C to exit monitoring${NC}"

  sleep 3
done
