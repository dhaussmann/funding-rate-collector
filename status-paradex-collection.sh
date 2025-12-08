#!/bin/bash

# Quick status check für Paradex Collection
# Zeigt aktuellen Status ohne Loop

set -e

DB_PATH="./funding-data.db"

# Finde neuestes Log-Verzeichnis
LOG_DIR=$(find ./logs -maxdepth 1 -type d -name "paradex-recent-*" 2>/dev/null | sort -r | head -1)

if [ -z "$LOG_DIR" ]; then
  echo "No active collection found in ./logs/paradex-recent-*"
  echo "Checking database only..."
  LOG_DIR=""
fi

# Farben
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${CYAN}=== Paradex Collection Status ===${NC}\n"

# DB Records
echo -e "${GREEN}Database Records:${NC}"
unified_count=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM unified_funding_rates WHERE exchange = 'paradex';" 2>/dev/null || echo "0")
hourly_count=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM paradex_hourly_averages;" 2>/dev/null || echo "0")
echo -e "  unified_funding_rates:   ${CYAN}${unified_count}${NC}"
echo -e "  paradex_hourly_averages: ${CYAN}${hourly_count}${NC}"

# Zeitspanne der Daten
echo -e "\n${GREEN}Data Range:${NC}"
sqlite3 "$DB_PATH" "SELECT
  datetime(MIN(collected_at)/1000, 'unixepoch') as first_entry,
  datetime(MAX(collected_at)/1000, 'unixepoch') as last_entry,
  COUNT(DISTINCT trading_pair) as markets
FROM unified_funding_rates WHERE exchange = 'paradex';" 2>/dev/null | awk -F'|' '{
  if (NF == 3) {
    print "  First entry: " $1
    print "  Last entry:  " $2
    print "  Markets:     " $3
  }
}' || echo "  No data yet"

# Letzte 10 Einträge
echo -e "\n${GREEN}Latest 10 Entries:${NC}"
sqlite3 -header -column "$DB_PATH" "SELECT
  datetime(collected_at/1000, 'unixepoch') as time,
  trading_pair as market,
  printf('%.6f', funding_rate_percent) as rate_pct,
  printf('%.2f', annualized_rate) as annual
FROM unified_funding_rates
WHERE exchange = 'paradex'
ORDER BY collected_at DESC
LIMIT 10;" 2>/dev/null || echo "  No data yet"

# Worker Status
if [ -n "$LOG_DIR" ]; then
  echo -e "\n${GREEN}Worker Logs (last line from each):${NC}"
  for i in {1..5}; do
    log_file="$LOG_DIR/worker_${i}.log"
    if [ -f "$log_file" ]; then
      last_line=$(tail -1 "$log_file" 2>/dev/null)
      echo -e "  Worker $i: $last_line"
    else
      echo -e "  Worker $i: ${YELLOW}No log file${NC}"
    fi
  done

  # Fehler in Logs
  echo -e "\n${GREEN}Recent Errors:${NC}"
  error_count=0
  for i in {1..5}; do
    log_file="$LOG_DIR/worker_${i}.log"
    if [ -f "$log_file" ]; then
      errors=$(grep -E "✗|Error|error" "$log_file" 2>/dev/null | tail -5)
      if [ -n "$errors" ]; then
        echo -e "  ${YELLOW}Worker $i:${NC}"
        echo "$errors" | sed 's/^/    /'
        error_count=$((error_count + 1))
      fi
    fi
  done

  if [ $error_count -eq 0 ]; then
    echo -e "  ${GREEN}No errors found${NC}"
  fi
else
  echo -e "\n${YELLOW}No active collection logs found${NC}"
fi

echo ""
