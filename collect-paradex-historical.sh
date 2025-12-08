#!/bin/bash

# ============================================
# Konfiguration
# ============================================
START_TIME=1735689600  # 2025-01-01 00:00:00 UTC (SEKUNDEN!)
END_TIME=$(date +%s)   # Jetzt (SEKUNDEN!)
RATE_LIMIT=1           # Sekunden zwischen Requests
PAGE_DELAY=0.2         # Sekunden zwischen Paginierungs-Requests

# ============================================
# Farben
# ============================================
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

# ============================================
# D1 Datenbank Name
# ============================================
DB_NAME="funding-rates-db"

# ============================================
# Statistiken
# ============================================
SUCCESS=0
FAILED=0
TOTAL_RAW_RECORDS=0
TOTAL_HOURLY_RECORDS=0

echo -e "${BLUE}=========================================${NC}"
echo -e "${BLUE}Paradex Historical Data Collection${NC}"
echo -e "${BLUE}With Pagination & Hourly Aggregation${NC}"
echo -e "${BLUE}=========================================${NC}"
echo "Period: 2025-01-01 to $(date '+%Y-%m-%d %H:%M:%S')"
echo "Start Time: $START_TIME (seconds)"
echo "End Time: $END_TIME (seconds)"
echo ""
echo -e "${YELLOW}Note: API returns 5-second snapshots${NC}"
echo -e "${YELLOW}      Aggregating to hourly averages${NC}"
echo ""

# ============================================
# Symbole sammeln
# ============================================
echo -e "${YELLOW}Fetching Paradex markets...${NC}"

MARKETS_RESPONSE=$(curl -s "https://api.prod.paradex.trade/v1/markets/summary?market=ALL")

# Erstelle ein Array mit market symbols (nur PERP)
MARKETS=$(echo "$MARKETS_RESPONSE" | jq -r '.results[] | select(.symbol | endswith("-PERP")) | .symbol' | sort -u)

TOTAL_COUNT=$(echo "$MARKETS" | wc -l | tr -d ' ')

echo -e "${GREEN}✓ Found $TOTAL_COUNT perpetual markets${NC}"
echo ""
echo -e "${YELLOW}Starting collection...${NC}"
echo ""

CURRENT=0

# ============================================
# Für jeden Market historische Daten sammeln
# ============================================
while IFS= read -r MARKET; do
  ((CURRENT++))
  PERCENT=$((CURRENT * 100 / TOTAL_COUNT))
  BASE_ASSET=$(echo "$MARKET" | cut -d'-' -f1)

  printf "[%3d%%] (%3d/%3d) %-15s " "$PERCENT" "$CURRENT" "$TOTAL_COUNT" "$MARKET"

  MARKET_RAW_RECORDS=0
  NEXT_URL="https://api.prod.paradex.trade/v1/funding/data?market=${MARKET}&start_at=${START_TIME}"
  PAGE=1

  # Erstelle temporäre Datei für alle 5-Sekunden Daten
  RAW_TEMP=$(mktemp)

  # ==========================================
  # Paginierung: Sammle alle 5-Sekunden Daten
  # ==========================================
  while [ -n "$NEXT_URL" ]; do
    RESPONSE=$(curl -s "$NEXT_URL")

    # Prüfe ob Daten vorhanden sind
    RECORDS_COUNT=$(echo "$RESPONSE" | jq '.results | length' 2>/dev/null)

    if [ "$RECORDS_COUNT" -gt 0 ] 2>/dev/null; then
      # Speichere alle results in temp file
      echo "$RESPONSE" | jq -c '.results[]' >> "$RAW_TEMP"
      MARKET_RAW_RECORDS=$((MARKET_RAW_RECORDS + RECORDS_COUNT))

      # Hole next URL
      NEXT_URL=$(echo "$RESPONSE" | jq -r '.next // empty')

      # Wenn next URL vorhanden, vervollständige sie
      if [ -n "$NEXT_URL" ]; then
        NEXT_URL="https://api.prod.paradex.trade${NEXT_URL}"
        ((PAGE++))
        sleep $PAGE_DELAY
      fi
    else
      NEXT_URL=""
    fi
  done

  # ==========================================
  # Aggregiere auf stündliche Werte
  # ==========================================
  if [ $MARKET_RAW_RECORDS -gt 0 ]; then
    HOURLY_TEMP=$(mktemp)

    # Gruppiere nach Stunde und berechne Durchschnitt
    # created_at ist in Millisekunden, funding_rate ist String
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
      # Berechne Prozent und Annualisierung
      # Paradex verwendet 8h Funding Intervalle (3x täglich wie Binance)
      FUNDING_RATE_PERCENT=$(echo "$AVG_RATE * 100" | bc -l)
      ANNUALIZED_RATE=$(echo "$AVG_RATE * 100 * 3 * 365" | bc -l)

      # Schreibe SQL für unified_funding_rates
      echo "INSERT OR IGNORE INTO unified_funding_rates (exchange, symbol, trading_pair, funding_rate, funding_rate_percent, annualized_rate, collected_at) VALUES ('paradex', '$BASE_ASSET', '$MARKET', $AVG_RATE, $FUNDING_RATE_PERCENT, $ANNUALIZED_RATE, $HOUR);" >> "$HOURLY_TEMP"

      # Schreibe SQL für paradex_hourly_averages
      # Note: funding_premium, mark_price, etc. werden hier als 0/NULL gesetzt,
      # da wir nur funding_rate aus der History-API haben
      echo "INSERT OR IGNORE INTO paradex_hourly_averages (symbol, base_asset, hour_timestamp, avg_funding_rate, avg_funding_premium, avg_mark_price, avg_underlying_price, funding_index_start, funding_index_end, funding_index_delta, sample_count) VALUES ('$MARKET', '$BASE_ASSET', $HOUR, $AVG_RATE, 0, 0, NULL, 0, 0, 0, $SAMPLE_COUNT);" >> "$HOURLY_TEMP"
    done

    # Führe alle Inserts aus
    if [ -s "$HOURLY_TEMP" ]; then
      HOURLY_COUNT=$(grep -c "unified_funding_rates" "$HOURLY_TEMP" 2>/dev/null || echo 0)

      wrangler d1 execute "$DB_NAME" --remote --file="$HOURLY_TEMP" > /dev/null 2>&1

      if [ $? -eq 0 ]; then
        printf "${GREEN}✓ %4d raw → %3d hourly (${PAGE} pages)${NC}\n" "$MARKET_RAW_RECORDS" "$HOURLY_COUNT"
        ((SUCCESS++))
        TOTAL_RAW_RECORDS=$((TOTAL_RAW_RECORDS + MARKET_RAW_RECORDS))
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

  rm -f "$RAW_TEMP"

  sleep $RATE_LIMIT
done <<< "$MARKETS"

# ============================================
# Zusammenfassung
# ============================================
echo ""
echo -e "${BLUE}=========================================${NC}"
echo -e "${BLUE}Collection Summary${NC}"
echo -e "${BLUE}=========================================${NC}"
echo "Total markets processed: $TOTAL_COUNT"
echo -e "Success: ${GREEN}$SUCCESS${NC}"
echo -e "No data: ${YELLOW}$FAILED${NC}"
echo -e "Total raw records: ${GREEN}$TOTAL_RAW_RECORDS${NC}"
echo -e "Total hourly records: ${GREEN}$TOTAL_HOURLY_RECORDS${NC}"
echo ""

# ============================================
# Datenbank-Statistiken
# ============================================
echo -e "${YELLOW}Database Statistics:${NC}"
wrangler d1 execute "$DB_NAME" --remote --command "
  SELECT
    COUNT(*) as total_records,
    COUNT(DISTINCT symbol) as unique_symbols,
    datetime(MIN(collected_at)/1000, 'unixepoch') as earliest,
    datetime(MAX(collected_at)/1000, 'unixepoch') as latest
  FROM unified_funding_rates
  WHERE exchange = 'paradex'
"

echo ""
echo -e "${YELLOW}Hourly aggregation statistics:${NC}"
wrangler d1 execute "$DB_NAME" --remote --command "
  SELECT
    COUNT(*) as total_hours,
    COUNT(DISTINCT symbol) as unique_symbols,
    SUM(sample_count) as total_samples,
    AVG(sample_count) as avg_samples_per_hour,
    datetime(MIN(hour_timestamp)/1000, 'unixepoch') as earliest,
    datetime(MAX(hour_timestamp)/1000, 'unixepoch') as latest
  FROM paradex_hourly_averages
"

echo ""
echo -e "${GREEN}✓ Collection complete!${NC}"
