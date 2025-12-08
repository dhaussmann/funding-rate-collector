#!/bin/bash

# ============================================
# Paradex Historical Worker Script
# Sammelt Daten für eine Teilmenge von Markets
# ============================================

# Parameter
WORKER_ID=$1
MARKETS_FILE=$2
START_TIME=$3
END_TIME=$4

if [ -z "$WORKER_ID" ] || [ -z "$MARKETS_FILE" ] || [ -z "$START_TIME" ] || [ -z "$END_TIME" ]; then
  echo "Usage: $0 <worker_id> <markets_file> <start_time> <end_time>"
  exit 1
fi

# Konfiguration
RATE_LIMIT=0.2            # 5 req/s pro Worker (5 Workers * 5 = 25 req/s total)
CHUNK_SIZE=300000         # 5 Minuten
SAMPLE_INTERVAL=3600000   # 1 Stunde
DB_NAME="funding-rates-db"

# Farben
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Statistiken
SUCCESS=0
FAILED=0
TOTAL_RAW_RECORDS=0
TOTAL_HOURLY_RECORDS=0

echo -e "${BLUE}[Worker $WORKER_ID] Started${NC}"
echo "Markets file: $MARKETS_FILE"

START_DATE=$(date -d "@$((START_TIME / 1000))" '+%Y-%m-%d' 2>/dev/null || date -r $((START_TIME / 1000)) '+%Y-%m-%d' 2>/dev/null)
END_DATE=$(date -d "@$((END_TIME / 1000))" '+%Y-%m-%d' 2>/dev/null || date -r $((END_TIME / 1000)) '+%Y-%m-%d' 2>/dev/null)

echo "Period: $START_DATE to $END_DATE"
echo ""

TOTAL_MARKETS=$(wc -l < "$MARKETS_FILE")
CURRENT=0

while IFS= read -r MARKET; do
  ((CURRENT++))
  PERCENT=$((CURRENT * 100 / TOTAL_MARKETS))
  BASE_ASSET=$(echo "$MARKET" | cut -d'-' -f1)

  printf "[W%d][%3d%%] (%3d/%3d) %-15s " "$WORKER_ID" "$PERCENT" "$CURRENT" "$TOTAL_MARKETS" "$MARKET"

  MARKET_RAW_RECORDS=0
  CHUNKS_PROCESSED=0
  RAW_TEMP=$(mktemp)

  # Sammle Daten
  SAMPLE_TIME=$START_TIME
  TOTAL_SAMPLES=$(( (END_TIME - START_TIME) / SAMPLE_INTERVAL ))

  while [ $SAMPLE_TIME -lt $END_TIME ]; do
    CHUNK_END=$((SAMPLE_TIME + CHUNK_SIZE))

    RESPONSE=$(curl -s "https://api.prod.paradex.trade/v1/funding/data?market=${MARKET}&start_at=${SAMPLE_TIME}&end_at=${CHUNK_END}")
    RECORDS_COUNT=$(echo "$RESPONSE" | jq '.results | length' 2>/dev/null)

    if [ "$RECORDS_COUNT" -gt 0 ] 2>/dev/null; then
      echo "$RESPONSE" | jq -c '.results[]' >> "$RAW_TEMP"
      MARKET_RAW_RECORDS=$((MARKET_RAW_RECORDS + RECORDS_COUNT))
      ((CHUNKS_PROCESSED++))
    fi

    SAMPLE_TIME=$((SAMPLE_TIME + SAMPLE_INTERVAL))
    sleep $RATE_LIMIT
  done

  # Aggregiere und speichere
  if [ $MARKET_RAW_RECORDS -gt 0 ]; then
    HOURLY_TEMP=$(mktemp)

    cat "$RAW_TEMP" | jq -r '
      (.created_at / 3600000 | floor * 3600000) as $hour |
      (.funding_rate | tonumber) as $rate |
      "\($hour):\($rate)"
    ' | sort -n | awk -F: '
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
      # Verwende awk statt bc für bessere Handhabung von wissenschaftlicher Notation
      # LC_NUMERIC=C erzwingt Punkt als Dezimaltrennzeichen (wichtig für SQL)
      FUNDING_RATE_PERCENT=$(LC_NUMERIC=C awk "BEGIN {printf \"%.18f\", $AVG_RATE * 100}")
      ANNUALIZED_RATE=$(LC_NUMERIC=C awk "BEGIN {printf \"%.18f\", $AVG_RATE * 100 * 3 * 365}")

      echo "INSERT OR IGNORE INTO unified_funding_rates (exchange, symbol, trading_pair, funding_rate, funding_rate_percent, annualized_rate, collected_at) VALUES ('paradex', '$BASE_ASSET', '$MARKET', $AVG_RATE, $FUNDING_RATE_PERCENT, $ANNUALIZED_RATE, $HOUR);" >> "$HOURLY_TEMP"
      echo "INSERT OR IGNORE INTO paradex_hourly_averages (symbol, base_asset, hour_timestamp, avg_funding_rate, avg_funding_premium, avg_mark_price, avg_underlying_price, funding_index_start, funding_index_end, funding_index_delta, sample_count) VALUES ('$MARKET', '$BASE_ASSET', $HOUR, $AVG_RATE, 0, 0, NULL, 0, 0, 0, $SAMPLE_COUNT);" >> "$HOURLY_TEMP"
    done

    if [ -s "$HOURLY_TEMP" ]; then
      HOURLY_COUNT=$(grep -c "unified_funding_rates" "$HOURLY_TEMP" 2>/dev/null || echo 0)
      wrangler d1 execute "$DB_NAME" --remote --file="$HOURLY_TEMP" > /dev/null 2>&1

      if [ $? -eq 0 ]; then
        printf "${GREEN}✓ %d hourly${NC}\n" "$HOURLY_COUNT"
        ((SUCCESS++))
        TOTAL_RAW_RECORDS=$((TOTAL_RAW_RECORDS + MARKET_RAW_RECORDS))
        TOTAL_HOURLY_RECORDS=$((TOTAL_HOURLY_RECORDS + HOURLY_COUNT))
      else
        printf "${RED}✗ DB error${NC}\n"
        ((FAILED++))
      fi
    fi

    rm -f "$HOURLY_TEMP"
  else
    printf "${YELLOW}⚠ No data${NC}\n"
    ((FAILED++))
  fi

  rm -f "$RAW_TEMP"
done < "$MARKETS_FILE"

echo ""
echo -e "${BLUE}[Worker $WORKER_ID] Summary${NC}"
echo "Success: ${GREEN}$SUCCESS${NC}"
echo "Failed: ${YELLOW}$FAILED${NC}"
echo "Total records: ${GREEN}$TOTAL_HOURLY_RECORDS${NC}"
