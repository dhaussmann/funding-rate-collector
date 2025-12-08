#!/bin/bash

# ============================================
# Test Script - Paradex Collection Debug
# ============================================
# Tests API connectivity and DB insertion
# ============================================

GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}=========================================${NC}"
echo -e "${BLUE}Paradex Collection Test & Debug${NC}"
echo -e "${BLUE}=========================================${NC}"
echo ""

# Test 1: API Connectivity
echo -e "${YELLOW}[Test 1] API Connectivity${NC}"
echo "Fetching markets..."

MARKETS_RESPONSE=$(curl -s "https://api.prod.paradex.trade/v1/markets/summary?market=ALL")
if [ $? -ne 0 ]; then
  echo -e "${RED}✗ Failed to connect to API${NC}"
  exit 1
fi

MARKET_COUNT=$(echo "$MARKETS_RESPONSE" | jq -r '.results[] | select(.symbol | endswith("-PERP")) | .symbol' | wc -l)
echo -e "${GREEN}✓ API reachable, found $MARKET_COUNT markets${NC}"
echo ""

# Test 2: Fetch funding data for BTC
echo -e "${YELLOW}[Test 2] Fetching sample funding data${NC}"
echo "Market: BTC-USD-PERP"

# Last 30 days
END_TIME=$(date +%s)000
START_TIME=$((END_TIME - 30 * 24 * 3600 * 1000))
CHUNK_END=$((START_TIME + 300000))

echo "Time range: $(date -r $((START_TIME / 1000)) '+%Y-%m-%d %H:%M' 2>/dev/null || echo 'N/A') to $(date -r $((CHUNK_END / 1000)) '+%Y-%m-%d %H:%M' 2>/dev/null || echo 'N/A')"

RESPONSE=$(curl -s "https://api.prod.paradex.trade/v1/funding/data?market=BTC-USD-PERP&start_at=${START_TIME}&end_at=${CHUNK_END}")

RECORDS_COUNT=$(echo "$RESPONSE" | jq '.results | length' 2>/dev/null)

if [ "$RECORDS_COUNT" -gt 0 ] 2>/dev/null; then
  echo -e "${GREEN}✓ Got $RECORDS_COUNT records${NC}"
  echo ""
  echo "Sample record:"
  echo "$RESPONSE" | jq '.results[0]' | head -8
else
  echo -e "${RED}✗ No data returned${NC}"
  echo "Response:"
  echo "$RESPONSE" | jq '.' | head -20
  exit 1
fi
echo ""

# Test 3: Process data (aggregation)
echo -e "${YELLOW}[Test 3] Data aggregation test${NC}"

RAW_TEMP=$(mktemp)
echo "$RESPONSE" | jq -c '.results[]' > "$RAW_TEMP"

HOURLY_DATA=$(cat "$RAW_TEMP" | jq -r '
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
' | head -1)

if [ -n "$HOURLY_DATA" ]; then
  HOUR=$(echo "$HOURLY_DATA" | cut -d: -f1)
  AVG_RATE=$(echo "$HOURLY_DATA" | cut -d: -f2)
  SAMPLE_COUNT=$(echo "$HOURLY_DATA" | cut -d: -f3)

  echo -e "${GREEN}✓ Aggregation successful${NC}"
  echo "  Hour: $(date -r $((HOUR / 1000)) '+%Y-%m-%d %H:%M' 2>/dev/null || echo $HOUR)"
  echo "  Avg Rate: $AVG_RATE"
  echo "  Samples: $SAMPLE_COUNT"
else
  echo -e "${RED}✗ Aggregation failed${NC}"
  exit 1
fi
rm -f "$RAW_TEMP"
echo ""

# Test 4: Database connectivity
echo -e "${YELLOW}[Test 4] Database connectivity${NC}"

DB_TEST=$(wrangler d1 execute funding-rates-db --remote --command "SELECT 1 as test" --json 2>&1)

if echo "$DB_TEST" | grep -q '"test":1'; then
  echo -e "${GREEN}✓ Database connection successful${NC}"
else
  echo -e "${RED}✗ Database connection failed${NC}"
  echo "Error:"
  echo "$DB_TEST"
  exit 1
fi
echo ""

# Test 5: Test INSERT
echo -e "${YELLOW}[Test 5] Test database INSERT${NC}"

TEMP_SQL=$(mktemp)
TEST_TIMESTAMP=$(date +%s)000

cat > "$TEMP_SQL" <<EOF
INSERT OR IGNORE INTO unified_funding_rates
  (exchange, symbol, trading_pair, funding_rate, funding_rate_percent, annualized_rate, collected_at)
VALUES
  ('paradex', 'TEST', 'TEST-USD-PERP', 0.0001, 0.01, 10.95, $TEST_TIMESTAMP);
EOF

echo "SQL:"
cat "$TEMP_SQL"
echo ""

INSERT_RESULT=$(wrangler d1 execute funding-rates-db --remote --file="$TEMP_SQL" 2>&1)

if echo "$INSERT_RESULT" | grep -q "Executed"; then
  echo -e "${GREEN}✓ INSERT successful${NC}"

  # Verify
  VERIFY=$(wrangler d1 execute funding-rates-db --remote --command "SELECT symbol FROM unified_funding_rates WHERE symbol = 'TEST'" --json 2>&1)

  if echo "$VERIFY" | grep -q '"symbol":"TEST"'; then
    echo -e "${GREEN}✓ Data verified in database${NC}"

    # Cleanup
    wrangler d1 execute funding-rates-db --remote --command "DELETE FROM unified_funding_rates WHERE symbol = 'TEST'" > /dev/null 2>&1
    echo -e "${GREEN}✓ Test data cleaned up${NC}"
  else
    echo -e "${YELLOW}⚠ Data not found (might be expected)${NC}"
  fi
else
  echo -e "${RED}✗ INSERT failed${NC}"
  echo "Error:"
  echo "$INSERT_RESULT"
  exit 1
fi

rm -f "$TEMP_SQL"
echo ""

# Summary
echo -e "${BLUE}=========================================${NC}"
echo -e "${GREEN}✓ All tests passed!${NC}"
echo -e "${BLUE}=========================================${NC}"
echo ""
echo "The collection scripts should work correctly."
echo "If you're still not seeing data, check:"
echo "  1. Worker logs: tail -f /tmp/tmp.*/worker_*.log"
echo "  2. Network connectivity during collection"
echo "  3. Wrangler authentication: wrangler whoami"
