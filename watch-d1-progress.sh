#!/bin/bash

# Watch-Script für Cloudflare D1 Datenbank
# Zeigt alle 10 Sekunden den aktuellen Status

DB_NAME="funding-rates-db"

# Finde Log-Verzeichnis
find_log_dir() {
  find ./logs -maxdepth 1 -type d -name "paradex-recent-*" 2>/dev/null | sort -r | head -1
}

# Farben
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${CYAN}=== Paradex Collection Progress (D1 Database) ===${NC}"
echo "Updating every 10 seconds... (Ctrl+C to exit)"
echo ""

while true; do
  clear
  echo -e "${CYAN}=== Paradex Collection Progress ===${NC}"
  echo "Time: $(date '+%Y-%m-%d %H:%M:%S')"
  echo ""

  # DB Stats via Cloudflare D1
  echo -e "${GREEN}Database Records (Cloudflare D1):${NC}"
  echo -n "  Querying..."
  unified_count=$(npx wrangler d1 execute "$DB_NAME" --remote --command "SELECT COUNT(*) as count FROM unified_funding_rates WHERE exchange = 'paradex';" 2>/dev/null | grep -A1 "count" | tail -1 | tr -d ' ' | tr -d '\n')

  if [ -z "$unified_count" ]; then
    unified_count="error"
  fi

  echo -e "\r  unified_funding_rates:   ${CYAN}${unified_count}${NC}    "
  echo ""

  # Worker Status
  LOG_DIR=$(find_log_dir)

  if [ -n "$LOG_DIR" ]; then
    echo -e "${GREEN}Worker Status:${NC}"
    for i in {1..5}; do
      log_file="$LOG_DIR/worker_${i}.log"
      if [ -f "$log_file" ]; then
        # Hole letzte Fortschritts-Zeile
        last_progress=$(grep -E "^\[W" "$log_file" 2>/dev/null | tail -1)
        if [ -n "$last_progress" ]; then
          echo "  $last_progress"
        else
          echo "  Worker $i: Starting..."
        fi
      else
        echo "  Worker $i: No log yet"
      fi
    done
    echo ""

    # Letzte 5 DB Einträge via D1
    echo -e "${GREEN}Latest 5 Entries (D1):${NC}"
    npx wrangler d1 execute "$DB_NAME" --remote --command "
      SELECT
        datetime(collected_at/1000, 'unixepoch') as time,
        trading_pair,
        printf('%.6f', funding_rate_percent) as rate
      FROM unified_funding_rates
      WHERE exchange = 'paradex'
      ORDER BY collected_at DESC
      LIMIT 5;
    " 2>/dev/null | tail -n +3 | head -6 | sed 's/^/  /'
  else
    echo -e "${YELLOW}No active collection found${NC}"
    echo "Start with: ./collect-paradex-recent.sh"
  fi

  echo ""
  echo -e "${YELLOW}Press Ctrl+C to exit${NC}"

  sleep 10
done
