#!/bin/bash

# ============================================
# Debug Script - Single Market Test
# ============================================
# Tests the complete flow for ONE market
# Shows all generated SQL and results
# ============================================

GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

DB_NAME="funding-rates-db"
MARKET="BTC-USD-PERP"
BASE_ASSET="BTC"

echo -e "${BLUE}=========================================${NC}"
echo -e "${BLUE}Paradex Single Market Debug${NC}"
echo -e "${BLUE}=========================================${NC}"
echo "Market: $MARKET"
echo ""

# Zeitraum: Letzte 24 Stunden
END_TIME=$(date +%s)000
START_TIME=$((END_TIME - 24 * 3600 * 1000))
CHUNK_SIZE=300000
SAMPLE_INTERVAL=3600000

echo "Period: Last 24 hours"
echo "Samples: $((24 / (SAMPLE_INTERVAL / 3600000)))"
echo ""

# Sammle Daten
echo -e "${YELLOW}Step 1: Collecting raw data...${NC}"

RAW_TEMP=$(mktemp)
SAMPLE_TIME=$START_TIME
SAMPLES_COLLECTED=0

while [ $SAMPLE_TIME -lt $END_TIME ]; do
  CHUNK_END=$((SAMPLE_TIME + CHUNK_SIZE))

  RESPONSE=$(curl -s "https://api.prod.paradex.trade/v1/funding/data?market=${MARKET}&start_at=${SAMPLE_TIME}&end_at=${CHUNK_END}")
  RECORDS_COUNT=$(echo "$RESPONSE" | jq '.results | length' 2>/dev/null)

  if [ "$RECORDS_COUNT" -gt 0 ] 2>/dev/null; then
    echo "$RESPONSE" | jq -c '.results[]' >> "$RAW_TEMP"
    ((SAMPLES_COLLECTED++))
  fi

  SAMPLE_TIME=$((SAMPLE_TIME + SAMPLE_INTERVAL))
  sleep 0.2
done

RAW_COUNT=$(wc -l < "$RAW_TEMP")
echo -e "${GREEN}✓ Collected $RAW_COUNT raw records from $SAMPLES_COLLECTED samples${NC}"
echo ""

# Zeige ein paar Beispiel-Datensätze
echo -e "${YELLOW}Sample raw data:${NC}"
head -3 "$RAW_TEMP" | jq '.'
echo ""

# Aggregiere
echo -e "${YELLOW}Step 2: Aggregating to hourly...${NC}"

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
  # LC_NUMERIC=C erzwingt Punkt als Dezimaltrennzeichen (wichtig für SQL)
  FUNDING_RATE_PERCENT=$(LC_NUMERIC=C awk "BEGIN {printf \"%.18f\", $AVG_RATE * 100}")
  ANNUALIZED_RATE=$(LC_NUMERIC=C awk "BEGIN {printf \"%.18f\", $AVG_RATE * 100 * 3 * 365}")

  echo "INSERT OR IGNORE INTO unified_funding_rates (exchange, symbol, trading_pair, funding_rate, funding_rate_percent, annualized_rate, collected_at) VALUES ('paradex', '$BASE_ASSET', '$MARKET', $AVG_RATE, $FUNDING_RATE_PERCENT, $ANNUALIZED_RATE, $HOUR);" >> "$HOURLY_TEMP"
  echo "INSERT OR IGNORE INTO paradex_hourly_averages (symbol, base_asset, hour_timestamp, avg_funding_rate, avg_funding_premium, avg_mark_price, avg_underlying_price, funding_index_start, funding_index_end, funding_index_delta, sample_count) VALUES ('$MARKET', '$BASE_ASSET', $HOUR, $AVG_RATE, 0, 0, NULL, 0, 0, 0, $SAMPLE_COUNT);" >> "$HOURLY_TEMP"
done

HOURLY_COUNT=$(grep -c "unified_funding_rates" "$HOURLY_TEMP" 2>/dev/null || echo 0)
echo -e "${GREEN}✓ Generated $HOURLY_COUNT hourly records${NC}"
echo ""

# Zeige generierte SQL
echo -e "${YELLOW}Step 3: Generated SQL (first 3 statements):${NC}"
head -3 "$HOURLY_TEMP"
echo "..."
echo ""

# Test: Insert in DB
echo -e "${YELLOW}Step 4: Inserting into database...${NC}"

echo "Command: wrangler d1 execute $DB_NAME --remote --file=$HOURLY_TEMP"
echo ""

INSERT_OUTPUT=$(wrangler d1 execute "$DB_NAME" --remote --file="$HOURLY_TEMP" 2>&1)
EXIT_CODE=$?

echo "Output:"
echo "$INSERT_OUTPUT"
echo ""

if [ $EXIT_CODE -eq 0 ]; then
  echo -e "${GREEN}✓ Insert command succeeded (exit code 0)${NC}"
else
  echo -e "${RED}✗ Insert command failed (exit code $EXIT_CODE)${NC}"
fi
echo ""

# Verify
echo -e "${YELLOW}Step 5: Verifying data in database...${NC}"

VERIFY_OUTPUT=$(wrangler d1 execute "$DB_NAME" --remote --command "
  SELECT
    COUNT(*) as count,
    datetime(MIN(collected_at)/1000, 'unixepoch') as oldest,
    datetime(MAX(collected_at)/1000, 'unixepoch') as newest
  FROM unified_funding_rates
  WHERE exchange = 'paradex' AND symbol = '$BASE_ASSET'
" 2>&1)

echo "$VERIFY_OUTPUT"
echo ""

if echo "$VERIFY_OUTPUT" | grep -q "null"; then
  echo -e "${RED}✗ No data found in database!${NC}"
  echo ""
  echo -e "${YELLOW}Possible issues:${NC}"
  echo "  1. SQL syntax error (check statement above)"
  echo "  2. Wrangler auth issue (run: wrangler whoami)"
  echo "  3. Database constraint violation"
  echo "  4. Silent failure in wrangler"
else
  echo -e "${GREEN}✓ Data successfully inserted!${NC}"
fi

# Cleanup
rm -f "$RAW_TEMP" "$HOURLY_TEMP"

echo ""
echo -e "${BLUE}Debug complete${NC}"
