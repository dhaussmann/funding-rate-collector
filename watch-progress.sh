#!/bin/bash

# Einfaches Watch-Script für den Fortschritt
# Zeigt alle 5 Sekunden den aktuellen Status

DB_PATH="./funding-data.db"

# Finde Log-Verzeichnis
find_log_dir() {
  find ./logs -maxdepth 1 -type d -name "paradex-recent-*" 2>/dev/null | sort -r | head -1
}

# Farben
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${CYAN}=== Paradex Collection Progress Watch ===${NC}"
echo "Updating every 5 seconds... (Ctrl+C to exit)"
echo ""

while true; do
  clear
  echo -e "${CYAN}=== Paradex Collection Progress ===${NC}"
  echo "Time: $(date '+%Y-%m-%d %H:%M:%S')"
  echo ""

  # DB Stats
  unified_count=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM unified_funding_rates WHERE exchange = 'paradex';" 2>/dev/null || echo "0")
  hourly_count=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM paradex_hourly_averages;" 2>/dev/null || echo "0")

  echo -e "${GREEN}Database Records:${NC}"
  echo "  unified_funding_rates:   $unified_count"
  echo "  paradex_hourly_averages: $hourly_count"
  echo ""

  # Worker Status
  LOG_DIR=$(find_log_dir)

  if [ -n "$LOG_DIR" ]; then
    echo -e "${GREEN}Worker Status:${NC}"
    for i in {1..5}; do
      log_file="$LOG_DIR/worker_${i}.log"
      if [ -f "$log_file" ]; then
        # Hole letzte Fortschritts-Zeile
        last_progress=$(grep -E "^\[" "$log_file" 2>/dev/null | tail -1)
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

    # Letzte 3 DB Einträge
    echo -e "${GREEN}Latest 3 Entries:${NC}"
    sqlite3 "$DB_PATH" "SELECT
      datetime(collected_at/1000, 'unixepoch') as time,
      trading_pair,
      printf('%.6f', funding_rate_percent) as rate
    FROM unified_funding_rates
    WHERE exchange = 'paradex'
    ORDER BY collected_at DESC
    LIMIT 3;" 2>/dev/null | while IFS='|' read -r time pair rate; do
      echo "  $time  $pair  $rate%"
    done
  else
    echo -e "${YELLOW}No active collection found${NC}"
    echo "Start with: ./collect-paradex-recent.sh"
  fi

  echo ""
  echo -e "${YELLOW}Press Ctrl+C to exit${NC}"

  sleep 5
done
