#!/bin/bash

# ============================================
# Konfiguration
# ============================================
START_TIME=1735689600000  # 2025-01-01 00:00:00 UTC (Millisekunden)
END_TIME=$(date +%s)000   # Jetzt (Millisekunden)
RATE_LIMIT=1              # Sekunden zwischen Requests

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
TOTAL_RECORDS=0

echo -e "${BLUE}=========================================${NC}"
echo -e "${BLUE}Aster Historical Data Collection${NC}"
echo -e "${BLUE}=========================================${NC}"
echo "Period: 2025-01-01 to $(date '+%Y-%m-%d %H:%M:%S')"
echo "Start Time: $START_TIME (milliseconds)"
echo "End Time: $END_TIME (milliseconds)"
echo ""

# ============================================
# Symbole sammeln
# ============================================
echo -e "${YELLOW}Fetching Aster symbols...${NC}"

EXCHANGE_INFO=$(curl -s "https://aster.wirewaving.workers.dev/fapi/v1/exchangeInfo")

# Hole alle aktiven PERPETUAL Contracts und extrahiere baseAsset und symbol
SYMBOLS=$(echo "$EXCHANGE_INFO" | jq -r '.symbols[] | select(.contractType=="PERPETUAL" and .status=="TRADING") | "\(.baseAsset):\(.symbol)"' | sort -u)

TOTAL_COUNT=$(echo "$SYMBOLS" | wc -l | tr -d ' ')

echo -e "${GREEN}✓ Found $TOTAL_COUNT active symbols${NC}"
echo ""
echo -e "${YELLOW}Starting collection...${NC}"
echo ""

CURRENT=0

# ============================================
# Für jedes Symbol historische Daten sammeln
# ============================================
while IFS= read -r ENTRY; do
  BASE_ASSET=$(echo "$ENTRY" | cut -d':' -f1)
  TRADING_PAIR=$(echo "$ENTRY" | cut -d':' -f2)
  
  ((CURRENT++))
  PERCENT=$((CURRENT * 100 / TOTAL_COUNT))
  printf "[%3d%%] (%3d/%3d) %-10s (%s) " "$PERCENT" "$CURRENT" "$TOTAL_COUNT" "$BASE_ASSET" "$TRADING_PAIR"
  
  # API Call zu Aster (max 1000 records per request)
  RESPONSE=$(curl -s "https://aster.wirewaving.workers.dev/fapi/v1/fundingRate?symbol=${TRADING_PAIR}&startTime=${START_TIME}&endTime=${END_TIME}&limit=1000")
  
  # Prüfe ob Daten vorhanden sind
  RECORDS_COUNT=$(echo "$RESPONSE" | jq '. | length' 2>/dev/null)
  
  if [ "$RECORDS_COUNT" -gt 0 ] 2>/dev/null; then
    # Erstelle temporäre Datei für Batch Insert
    TEMP_FILE=$(mktemp)
    
    # Sammle alle SQL Statements
    echo "$RESPONSE" | jq -c '.[]' | while read -r FUND_ENTRY; do
      FUNDING_RATE=$(echo "$FUND_ENTRY" | jq -r '.fundingRate')
      FUNDING_TIME=$(echo "$FUND_ENTRY" | jq -r '.fundingTime')
      
      # Berechne Prozent und Annualisierung (8h Intervalle = 3x täglich)
      FUNDING_RATE_PERCENT=$(echo "$FUNDING_RATE * 100" | bc -l)
      ANNUALIZED_RATE=$(echo "$FUNDING_RATE * 100 * 3 * 365" | bc -l)
      
      # Schreibe SQL in temp file
      echo "INSERT OR IGNORE INTO unified_funding_rates (exchange, symbol, trading_pair, funding_rate, funding_rate_percent, annualized_rate, collected_at) VALUES ('aster', '$BASE_ASSET', '$TRADING_PAIR', $FUNDING_RATE, $FUNDING_RATE_PERCENT, $ANNUALIZED_RATE, $FUNDING_TIME);" >> "$TEMP_FILE"
      echo "INSERT OR IGNORE INTO aster_funding_history (symbol, base_asset, funding_rate, funding_time, collected_at) VALUES ('$TRADING_PAIR', '$BASE_ASSET', $FUNDING_RATE, $FUNDING_TIME, $FUNDING_TIME);" >> "$TEMP_FILE"
    done
    
    # Führe alle Inserts auf einmal aus - MIT --remote FLAG
    if [ -s "$TEMP_FILE" ]; then
      wrangler d1 execute "$DB_NAME" --remote --file="$TEMP_FILE" > /dev/null 2>&1
    fi
    
    rm -f "$TEMP_FILE"
    
    printf "${GREEN}✓ %4d records${NC}\n" "$RECORDS_COUNT"
    ((SUCCESS++))
    TOTAL_RECORDS=$((TOTAL_RECORDS + RECORDS_COUNT))
  else
    printf "${YELLOW}⚠ No data${NC}\n"
    ((FAILED++))
  fi
  
  sleep $RATE_LIMIT
done <<< "$SYMBOLS"

# ============================================
# Zusammenfassung
# ============================================
echo ""
echo -e "${BLUE}=========================================${NC}"
echo -e "${BLUE}Collection Summary${NC}"
echo -e "${BLUE}=========================================${NC}"
echo "Total symbols processed: $TOTAL_COUNT"
echo -e "Success: ${GREEN}$SUCCESS${NC}"
echo -e "No data: ${YELLOW}$FAILED${NC}"
echo -e "Total records: ${GREEN}$TOTAL_RECORDS${NC}"
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
  WHERE exchange = 'aster'
"

echo ""
echo -e "${GREEN}✓ Collection complete!${NC}"
