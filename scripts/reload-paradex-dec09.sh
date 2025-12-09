#!/bin/bash

# ============================================
# Reload Paradex Data for December 9, 2025
# ============================================

# Zeitbereich: 9. Dezember 2025, 00:00:00 - 23:59:59 UTC
START_TIME=1733702400000  # 2025-12-09 00:00:00 UTC
END_TIME=1733788799999    # 2025-12-09 23:59:59 UTC

# Konfiguration
SAMPLE_INTERVAL=3600000   # 1 Stunde (für Sampling)
DB_NAME="funding-rates-db"

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
echo -e "${YELLOW}Collecting hourly data for each market...${NC}"
echo ""

# Statistiken
SUCCESS=0
FAILED=0
TOTAL_HOURLY_RECORDS=0
CURRENT=0

# Für jeden Market
while IFS= read -r MARKET; do
  ((CURRENT++))
  PERCENT=$((CURRENT * 100 / TOTAL_COUNT))
  BASE_ASSET=$(echo "$MARKET" | cut -d'-' -f1)

  printf "[%3d%%] (%3d/%3d) %-20s " "$PERCENT" "$CURRENT" "$TOTAL_COUNT" "$MARKET"

  # Sammle Daten für den ganzen Tag
  RESPONSE=$(curl -s "https://api.prod.paradex.trade/v1/funding/data?market=${MARKET}&start_at=${START_TIME}&end_at=${END_TIME}")
  RECORDS_COUNT=$(echo "$RESPONSE" | jq '.results | length' 2>/dev/null)

  if [ "$RECORDS_COUNT" -gt 0 ] 2>/dev/null; then
    # Aggregiere nach Stunden
    HOURLY_TEMP=$(mktemp)

    echo "$RESPONSE" | jq -r '.results[] |
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
        printf "${GREEN}✓ %d hours${NC}\n" "$HOURLY_COUNT"
        ((SUCCESS++))
        TOTAL_HOURLY_RECORDS=$((TOTAL_HOURLY_RECORDS + HOURLY_COUNT))
      else
        printf "${RED}✗ DB error${NC}\n"
        ((FAILED++))
      fi
    else
      printf "${YELLOW}⚠ No hourly data${NC}\n"
      ((FAILED++))
    fi

    rm -f "$HOURLY_TEMP"
  else
    printf "${YELLOW}⚠ No data${NC}\n"
    ((FAILED++))
  fi

  # Rate limiting: 0.2s pro Request = ~5 req/s
  sleep 0.2

done <<< "$MARKETS"

echo ""
echo -e "${BLUE}=========================================${NC}"
echo -e "${BLUE}Data Collection Complete!${NC}"
echo -e "${BLUE}=========================================${NC}"
echo -e "Success: ${GREEN}$SUCCESS${NC} markets"
echo -e "Failed: ${YELLOW}$FAILED${NC} markets"
echo -e "Total hourly records: ${GREEN}$TOTAL_HOURLY_RECORDS${NC}"
echo ""
echo -e "${GREEN}✓ December 9, 2025 data reloaded!${NC}"
echo ""
