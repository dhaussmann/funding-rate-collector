#!/bin/bash

# ============================================
# Konfiguration
# ============================================
START_TIME=1735689600  # 2025-01-01 00:00:00 UTC (SEKUNDEN!)
END_TIME=$(date +%s)   # Jetzt (SEKUNDEN!)
RATE_LIMIT=1           # Sekunden zwischen Requests

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
echo -e "${BLUE}Lighter Historical Data Collection${NC}"
echo -e "${BLUE}=========================================${NC}"
echo "Period: 2025-01-01 to $(date '+%Y-%m-%d %H:%M:%S')"
echo "Start Time: $START_TIME (seconds)"
echo "End Time: $END_TIME (seconds)"
echo ""

# ============================================
# Symbole und Markets sammeln
# ============================================
echo -e "${YELLOW}Fetching Lighter markets...${NC}"

MARKETS_RESPONSE=$(curl -s "https://mainnet.zklighter.elliot.ai/api/v1/orderBooks")

# Erstelle ein Array mit market_id und symbol
MARKETS=$(echo "$MARKETS_RESPONSE" | jq -r '.order_books[] | select(.status=="active") | "\(.market_id):\(.symbol)"')

TOTAL_COUNT=$(echo "$MARKETS" | wc -l | tr -d ' ')

echo -e "${GREEN}✓ Found $TOTAL_COUNT active markets${NC}"
echo ""
echo -e "${YELLOW}Starting collection...${NC}"
echo ""

CURRENT=0

# ============================================
# Für jeden Market historische Daten sammeln
# ============================================
while IFS= read -r MARKET; do
  MARKET_ID=$(echo "$MARKET" | cut -d':' -f1)
  SYMBOL=$(echo "$MARKET" | cut -d':' -f2)
  
  ((CURRENT++))
  PERCENT=$((CURRENT * 100 / TOTAL_COUNT))
  printf "[%3d%%] (%3d/%3d) %-10s (ID:%3s) " "$PERCENT" "$CURRENT" "$TOTAL_COUNT" "$SYMBOL" "$MARKET_ID"
  
  # API Call zu Lighter mit Zeitstempeln in SEKUNDEN
  RESPONSE=$(curl -s "https://mainnet.zklighter.elliot.ai/api/v1/fundings?market_id=${MARKET_ID}&resolution=1h&start_timestamp=${START_TIME}&end_timestamp=${END_TIME}&count_back=0")
  
  # Prüfe ob Daten vorhanden sind
  RECORDS_COUNT=$(echo "$RESPONSE" | jq '.fundings | length' 2>/dev/null)
  
  if [ "$RECORDS_COUNT" -gt 0 ] 2>/dev/null; then
    # Erstelle temporäre Datei für Batch Insert
    TEMP_FILE=$(mktemp)
    
    # Sammle alle SQL Statements
    echo "$RESPONSE" | jq -c '.fundings[]' | while read -r ENTRY; do
      RATE=$(echo "$ENTRY" | jq -r '.rate')
      DIRECTION=$(echo "$ENTRY" | jq -r '.direction')
      TIMESTAMP=$(echo "$ENTRY" | jq -r '.timestamp')
      
      # Konvertiere Timestamp von Sekunden zu Millisekunden
      TIMESTAMP_MS=$((TIMESTAMP * 1000))
      
      # WICHTIG: Lighter API gibt rate bereits in PROZENT zurück!
      # Beispiel: rate: 0.0012 bedeutet 0.0012% (nicht 0.12%)
      
      # Vorzeichen basierend auf Direction
      if [ "$DIRECTION" = "short" ]; then
        RATE_PERCENT=$(echo "-1 * $RATE" | bc -l)
      else
        RATE_PERCENT=$RATE
      fi
      
      # Konvertiere zu Dezimal für fundingRate Feld
      FUNDING_RATE=$(echo "$RATE_PERCENT / 100" | bc -l)  # 0.0012 / 100 = 0.000012
      
      # Annualisierung (stündlich * 24 * 365)
      ANNUALIZED_RATE=$(echo "$RATE_PERCENT * 24 * 365" | bc -l)  # 0.0012 * 24 * 365 = 10.512%
      
      # Schreibe SQL in temp file
      echo "INSERT OR IGNORE INTO unified_funding_rates (exchange, symbol, trading_pair, funding_rate, funding_rate_percent, annualized_rate, collected_at) VALUES ('lighter', '$SYMBOL', '$SYMBOL', $FUNDING_RATE, $RATE_PERCENT, $ANNUALIZED_RATE, $TIMESTAMP_MS);" >> "$TEMP_FILE"
      echo "INSERT OR IGNORE INTO lighter_funding_history (market_id, symbol, timestamp, rate, direction, collected_at) VALUES ($MARKET_ID, '$SYMBOL', $TIMESTAMP, $RATE, '$DIRECTION', $TIMESTAMP_MS);" >> "$TEMP_FILE"
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
  WHERE exchange = 'lighter'
"

echo ""
echo -e "${GREEN}✓ Collection complete!${NC}"