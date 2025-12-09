#!/bin/bash

# ============================================
# Reload Paradex Data for December 9, 2025
# ============================================
# API Limit: 1500 req/s - wir nutzen ~1200 req/s (sicher)
# Parallelisierung: 20 Workers @ 60 req/s = 1200 req/s total
# ============================================

# Zeitbereich: 9. Dezember 2025, 00:00:00 - 23:59:59 UTC
START_TIME=1733702400000  # 2025-12-09 00:00:00 UTC
END_TIME=1733788799999    # 2025-12-09 23:59:59 UTC

# Konfiguration
SAMPLE_INTERVAL=3600000   # 1 Stunde (für Sampling)
DB_NAME="funding-rates-db"
NUM_WORKERS=20            # Parallele Workers
SLEEP_TIME=0.0167         # ~60 req/s pro Worker (20 * 60 = 1200 req/s)

# Farben
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}=========================================${NC}"
echo -e "${BLUE}Reload Paradex Data - December 9, 2025${NC}"
echo -e "${BLUE}=========================================${NC}"
echo "Period: 2025-12-09 00:00:00 to 23:59:59 UTC"
echo ""

# Hole alle PERP Markets
echo -e "${YELLOW}Fetching Paradex markets...${NC}"
MARKETS=$(curl -s "https://api.prod.paradex.trade/v1/markets/summary?market=ALL" | \
  jq -r '.results[] | select(.symbol | endswith("-PERP")) | .symbol' | sort -u)
TOTAL_COUNT=$(echo "$MARKETS" | wc -l | tr -d ' ')

echo -e "${GREEN}✓ Found $TOTAL_COUNT perpetual markets${NC}"
echo ""
echo -e "${YELLOW}Splitting markets across $NUM_WORKERS workers...${NC}"

# Erstelle temporäres Verzeichnis
TEMP_DIR="./logs/reload-dec09-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$TEMP_DIR"

# Teile Markets auf Workers auf
MARKETS_PER_WORKER=$(( (TOTAL_COUNT + NUM_WORKERS - 1) / NUM_WORKERS ))
echo "$MARKETS" | split -l $MARKETS_PER_WORKER - "$TEMP_DIR/markets_"

WORKER_FILES=()
WORKER_COUNT=0
for file in "$TEMP_DIR"/markets_*; do
  ((WORKER_COUNT++))
  WORKER_FILES+=("$file")
  MARKET_COUNT=$(wc -l < "$file")
  echo "  Worker $WORKER_COUNT: $MARKET_COUNT markets"
done

echo ""
echo -e "${YELLOW}Starting $WORKER_COUNT workers in parallel...${NC}"
echo -e "${YELLOW}Target: ~1200 req/s total (60 req/s per worker)${NC}"
echo ""

# Worker Funktion
process_markets() {
  WORKER_ID=$1
  MARKETS_FILE=$2

  SUCCESS_LOCAL=0
  FAILED_LOCAL=0
  TOTAL_HOURLY_LOCAL=0
  CURRENT_LOCAL=0
  TOTAL_LOCAL=$(wc -l < "$MARKETS_FILE")

  while IFS= read -r MARKET; do
    ((CURRENT_LOCAL++))
    PERCENT=$((CURRENT_LOCAL * 100 / TOTAL_LOCAL))
    BASE_ASSET=$(echo "$MARKET" | cut -d'-' -f1)

    printf "[W%02d][%3d%%] (%2d/%2d) %-20s " "$WORKER_ID" "$PERCENT" "$CURRENT_LOCAL" "$TOTAL_LOCAL" "$MARKET" >> "$TEMP_DIR/worker_${WORKER_ID}.log"

    # Sammle ALLE Daten für den ganzen Tag (mit Chunking wie im Original-Script)
    ALL_DATA_TEMP=$(mktemp)
    CHUNK_SIZE=3600000        # 1 Stunde chunks
    SAMPLE_TIME=$START_TIME
    TOTAL_FETCHED=0

    while [ $SAMPLE_TIME -lt $END_TIME ]; do
      CHUNK_END=$((SAMPLE_TIME + CHUNK_SIZE))
      if [ $CHUNK_END -gt $END_TIME ]; then
        CHUNK_END=$END_TIME
      fi

      RESPONSE=$(curl -s "https://api.prod.paradex.trade/v1/funding/data?market=${MARKET}&start_at=${SAMPLE_TIME}&end_at=${CHUNK_END}")
      RECORDS_COUNT=$(echo "$RESPONSE" | jq '.results | length' 2>/dev/null)

      if [ "$RECORDS_COUNT" -gt 0 ] 2>/dev/null; then
        echo "$RESPONSE" | jq -c '.results[]' >> "$ALL_DATA_TEMP"
        TOTAL_FETCHED=$((TOTAL_FETCHED + RECORDS_COUNT))
      fi

      SAMPLE_TIME=$((SAMPLE_TIME + CHUNK_SIZE))
      sleep 0.01  # Kurze Pause zwischen Chunks
    done

    if [ $TOTAL_FETCHED -gt 0 ]; then
      # Aggregiere nach Stunden
      HOURLY_TEMP=$(mktemp)

      cat "$ALL_DATA_TEMP" | jq -r '
        (.created_at / 3600000 | floor * 3600000) as $hour |
        (.funding_rate | tonumber) as $rate |
        "\($hour):\($rate)"
      ' | sort -n | LC_NUMERIC=C awk -F: '
        {
          hour = $1
          rate = $2
          sum[hour] += rate
          count[hour]++
        }
        END {
          for (h in sum) {
            avg = sum[h] / count[h]
            print h ":" avg ":" count[h]
          }
        }
      ' | while IFS=: read -r HOUR AVG_RATE SAMPLE_COUNT; do
        # Berechne Prozent und annualisiert
        FUNDING_RATE_PERCENT=$(LC_NUMERIC=C awk "BEGIN {printf \"%.18f\", $AVG_RATE * 100}")
        ANNUALIZED_RATE=$(LC_NUMERIC=C awk "BEGIN {printf \"%.18f\", $AVG_RATE * 100 * 3 * 365}")

        # SQL Statements
        echo "INSERT OR IGNORE INTO unified_funding_rates (exchange, symbol, trading_pair, funding_rate, funding_rate_percent, annualized_rate, collected_at) VALUES ('paradex', '$BASE_ASSET', '$MARKET', $AVG_RATE, $FUNDING_RATE_PERCENT, $ANNUALIZED_RATE, $HOUR);" >> "$HOURLY_TEMP"
        echo "INSERT OR IGNORE INTO paradex_hourly_averages (symbol, base_asset, hour_timestamp, avg_funding_rate, avg_funding_premium, avg_mark_price, avg_underlying_price, funding_index_start, funding_index_end, funding_index_delta, sample_count) VALUES ('$MARKET', '$BASE_ASSET', $HOUR, $AVG_RATE, 0, 0, NULL, 0, 0, 0, $SAMPLE_COUNT);" >> "$HOURLY_TEMP"
      done

      if [ -s "$HOURLY_TEMP" ]; then
        HOURLY_COUNT=$(grep -c "unified_funding_rates" "$HOURLY_TEMP" 2>/dev/null || echo 0)
        npx wrangler d1 execute "$DB_NAME" --remote --file="$HOURLY_TEMP" > /dev/null 2>&1

        if [ $? -eq 0 ]; then
          printf "${GREEN}✓ %d hours (%d records)${NC}\n" "$HOURLY_COUNT" "$TOTAL_FETCHED" >> "$TEMP_DIR/worker_${WORKER_ID}.log"
          ((SUCCESS_LOCAL++))
          TOTAL_HOURLY_LOCAL=$((TOTAL_HOURLY_LOCAL + HOURLY_COUNT))
        else
          printf "${RED}✗ DB error${NC}\n" >> "$TEMP_DIR/worker_${WORKER_ID}.log"
          ((FAILED_LOCAL++))
        fi
      else
        printf "${YELLOW}⚠ No hourly data${NC}\n" >> "$TEMP_DIR/worker_${WORKER_ID}.log"
        ((FAILED_LOCAL++))
      fi

      rm -f "$HOURLY_TEMP"
      rm -f "$ALL_DATA_TEMP"
    else
      printf "${YELLOW}⚠ No data${NC}\n" >> "$TEMP_DIR/worker_${WORKER_ID}.log"
      ((FAILED_LOCAL++))
      rm -f "$ALL_DATA_TEMP"
    fi

    # Rate limiting: ~60 req/s pro Worker
    sleep $SLEEP_TIME

  done < "$MARKETS_FILE"

  echo "" >> "$TEMP_DIR/worker_${WORKER_ID}.log"
  echo "Worker $WORKER_ID Summary:" >> "$TEMP_DIR/worker_${WORKER_ID}.log"
  echo "Success: $SUCCESS_LOCAL" >> "$TEMP_DIR/worker_${WORKER_ID}.log"
  echo "Failed: $FAILED_LOCAL" >> "$TEMP_DIR/worker_${WORKER_ID}.log"
  echo "Hourly records: $TOTAL_HOURLY_LOCAL" >> "$TEMP_DIR/worker_${WORKER_ID}.log"
}

# Exportiere Funktionen und Variablen für Subshells
export -f process_markets
export START_TIME END_TIME DB_NAME SLEEP_TIME TEMP_DIR
export GREEN RED BLUE YELLOW NC

# Starte alle Worker parallel
PIDS=()
for i in "${!WORKER_FILES[@]}"; do
  WORKER_ID=$((i + 1))
  process_markets "$WORKER_ID" "${WORKER_FILES[$i]}" &
  PIDS+=($!)
  echo "Started Worker $WORKER_ID (PID: ${PIDS[$i]})"
done

echo ""
echo -e "${YELLOW}Workers running... Monitor: tail -f $TEMP_DIR/worker_*.log${NC}"
echo ""

# Warte auf alle Worker
START_EPOCH=$(date +%s)
for i in "${!PIDS[@]}"; do
  WORKER_ID=$((i + 1))
  wait ${PIDS[$i]}
  EXIT_CODE=$?

  if [ $EXIT_CODE -eq 0 ]; then
    echo -e "${GREEN}✓ Worker $WORKER_ID completed${NC}"
  else
    echo -e "${RED}✗ Worker $WORKER_ID failed (exit: $EXIT_CODE)${NC}"
  fi
done

END_EPOCH=$(date +%s)
DURATION=$((END_EPOCH - START_EPOCH))

# Sammle Statistiken
echo ""
echo -e "${BLUE}=========================================${NC}"
echo -e "${BLUE}Data Collection Complete!${NC}"
echo -e "${BLUE}=========================================${NC}"
printf "Total runtime: %d seconds\n" $DURATION

# Auswertung der Worker-Logs
TOTAL_SUCCESS=0
TOTAL_FAILED=0
TOTAL_RECORDS=0

for i in "${!WORKER_FILES[@]}"; do
  WORKER_ID=$((i + 1))
  if [ -f "$TEMP_DIR/worker_${WORKER_ID}.log" ]; then
    SUCCESS=$(grep "Success:" "$TEMP_DIR/worker_${WORKER_ID}.log" | tail -1 | awk '{print $2}')
    FAILED=$(grep "Failed:" "$TEMP_DIR/worker_${WORKER_ID}.log" | tail -1 | awk '{print $2}')
    RECORDS=$(grep "Hourly records:" "$TEMP_DIR/worker_${WORKER_ID}.log" | tail -1 | awk '{print $3}')

    TOTAL_SUCCESS=$((TOTAL_SUCCESS + SUCCESS))
    TOTAL_FAILED=$((TOTAL_FAILED + FAILED))
    TOTAL_RECORDS=$((TOTAL_RECORDS + RECORDS))
  fi
done

echo ""
echo -e "Success: ${GREEN}$TOTAL_SUCCESS${NC} markets"
echo -e "Failed: ${YELLOW}$TOTAL_FAILED${NC} markets"
echo -e "Total hourly records: ${GREEN}$TOTAL_RECORDS${NC}"
echo ""
echo -e "${GREEN}✓ December 9, 2025 data reloaded!${NC}"
echo -e "${YELLOW}Logs saved in: $TEMP_DIR${NC}"
echo ""

# Cleanup alte Market-Listen (behalte Logs)
rm -f "$TEMP_DIR"/markets_*
