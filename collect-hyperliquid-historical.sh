#!/bin/bash

# ============================================
# Konfiguration
# ============================================
START_TIME=1735689600000  # 2025-01-01 00:00:00 UTC (Millisekunden)
END_TIME=$(date +%s)000   # Jetzt (Millisekunden)
RATE_LIMIT=1              # Sekunden zwischen Requests
CHUNK_SIZE_DAYS=20         # Sammle in 7-Tages-Blöcken um unter 500 Records zu bleiben

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
echo -e "${BLUE}Hyperliquid Historical Data Collection${NC}"
echo -e "${BLUE}With Pagination Support${NC}"
echo -e "${BLUE}=========================================${NC}"

START_DATE=$(date -d "@$((START_TIME / 1000))" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date -r $((START_TIME / 1000)) '+%Y-%m-%d %H:%M:%S' 2>/dev/null)
END_DATE=$(date -d "@$((END_TIME / 1000))" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date -r $((END_TIME / 1000)) '+%Y-%m-%d %H:%M:%S' 2>/dev/null)

echo "Period: $START_DATE to $END_DATE"
echo "Chunk size: $CHUNK_SIZE_DAYS days"
echo ""

# ============================================
# Symbole sammeln
# ============================================
echo -e "${YELLOW}Fetching Hyperliquid symbols...${NC}"

HYPERLIQUID_RESPONSE=$(curl -s -X POST https://api.hyperliquid.xyz/info \
  -H "Content-Type: application/json" \
  -d '{"type":"meta"}')

HYPERLIQUID_SYMBOLS=$(echo "$HYPERLIQUID_RESPONSE" | jq -r '.universe[] | select(.isDelisted != true) | .name')
TOTAL_SYMBOLS=$(echo "$HYPERLIQUID_SYMBOLS" | wc -l | tr -d ' ')

echo -e "${GREEN}✓ Found $TOTAL_SYMBOLS active symbols${NC}"
echo ""

# Berechne wie viele Chunks wir brauchen
TOTAL_TIME_SPAN=$((END_TIME - START_TIME))
CHUNK_SIZE_MS=$((CHUNK_SIZE_DAYS * 24 * 60 * 60 * 1000))
TOTAL_CHUNKS=$(( (TOTAL_TIME_SPAN + CHUNK_SIZE_MS - 1) / CHUNK_SIZE_MS ))

echo -e "${YELLOW}Total time span: $((TOTAL_TIME_SPAN / 86400000)) days${NC}"
echo -e "${YELLOW}Will use $TOTAL_CHUNKS chunks of $CHUNK_SIZE_DAYS days${NC}"
echo ""
echo -e "${YELLOW}Starting collection...${NC}"
echo ""

CURRENT_SYMBOL=0

# ============================================
# Für jedes Symbol historische Daten sammeln
# ============================================
while IFS= read -r SYMBOL; do
  ((CURRENT_SYMBOL++))
  PERCENT=$((CURRENT_SYMBOL * 100 / TOTAL_SYMBOLS))
  
  SYMBOL_TOTAL_RECORDS=0
  CHUNK_START=$START_TIME
  
  # Sammle in Chunks
  for ((chunk=1; chunk<=TOTAL_CHUNKS; chunk++)); do
    CHUNK_END=$((CHUNK_START + CHUNK_SIZE_MS))
    if [ $CHUNK_END -gt $END_TIME ]; then
      CHUNK_END=$END_TIME
    fi
    
    printf "[%3d%%] (%3d/%3d) %-10s [Chunk %d/%d] " \
      "$PERCENT" "$CURRENT_SYMBOL" "$TOTAL_SYMBOLS" "$SYMBOL" "$chunk" "$TOTAL_CHUNKS"
    
    # API Call zu Hyperliquid
    RESPONSE=$(curl -s -X POST https://api.hyperliquid.xyz/info \
      -H "Content-Type: application/json" \
      -d "{\"type\":\"fundingHistory\",\"coin\":\"$SYMBOL\",\"startTime\":$CHUNK_START,\"endTime\":$CHUNK_END}")
    
    # Prüfe ob Daten vorhanden sind
    RECORDS_COUNT=$(echo "$RESPONSE" | jq '. | length' 2>/dev/null)
    
    if [ "$RECORDS_COUNT" -gt 0 ] 2>/dev/null; then
      # Erstelle temporäre Datei für Batch Insert
      TEMP_FILE=$(mktemp)
      
      # Sammle alle SQL Statements
      echo "$RESPONSE" | jq -c '.[]' | while read -r ENTRY; do
        FUNDING_RATE=$(echo "$ENTRY" | jq -r '.fundingRate')
        FUNDING_TIME=$(echo "$ENTRY" | jq -r '.time')
        
        # Konvertiere zu Millisekunden falls nötig
        if [ "$FUNDING_TIME" -lt 10000000000 ]; then
          FUNDING_TIME_MS=$((FUNDING_TIME * 1000))
        else
          FUNDING_TIME_MS=$FUNDING_TIME
        fi
        
        # Filtere nur Daten im gewünschten Zeitraum
        if [ "$FUNDING_TIME_MS" -ge "$START_TIME" ] && [ "$FUNDING_TIME_MS" -le "$END_TIME" ]; then
          FUNDING_RATE_PERCENT=$(echo "$FUNDING_RATE * 100" | bc -l)
          ANNUALIZED_RATE=$(echo "$FUNDING_RATE * 100 * 24 * 365" | bc -l)
          
          echo "INSERT OR IGNORE INTO unified_funding_rates (exchange, symbol, trading_pair, funding_rate, funding_rate_percent, annualized_rate, collected_at) VALUES ('hyperliquid', '$SYMBOL', '$SYMBOL', $FUNDING_RATE, $FUNDING_RATE_PERCENT, $ANNUALIZED_RATE, $FUNDING_TIME_MS);" >> "$TEMP_FILE"
          echo "INSERT OR IGNORE INTO hyperliquid_funding_history (coin, funding_rate, collected_at) VALUES ('$SYMBOL', $FUNDING_RATE, $FUNDING_TIME_MS);" >> "$TEMP_FILE"
        fi
      done
      
      # Führe Inserts aus
      if [ -s "$TEMP_FILE" ]; then
        INSERTED_COUNT=$(wc -l < "$TEMP_FILE")
        INSERTED_COUNT=$((INSERTED_COUNT / 2))
        
        wrangler d1 execute "$DB_NAME" --remote --file="$TEMP_FILE" > /dev/null 2>&1
        
        if [ $? -eq 0 ]; then
          printf "${GREEN}✓ %4d records${NC}\n" "$INSERTED_COUNT"
          SYMBOL_TOTAL_RECORDS=$((SYMBOL_TOTAL_RECORDS + INSERTED_COUNT))
        else
          printf "${RED}✗ DB error${NC}\n"
        fi
      else
        printf "${YELLOW}⚠ No new data${NC}\n"
      fi
      
      rm -f "$TEMP_FILE"
    else
      printf "${YELLOW}⚠ No data${NC}\n"
    fi
    
    # Nächster Chunk
    CHUNK_START=$CHUNK_END
    
    # Rate limiting
    sleep $RATE_LIMIT
    
    # Wenn wir am Ende sind, breche ab
    if [ $CHUNK_END -ge $END_TIME ]; then
      break
    fi
  done
  
  if [ $SYMBOL_TOTAL_RECORDS -gt 0 ]; then
    ((SUCCESS++))
    TOTAL_RECORDS=$((TOTAL_RECORDS + SYMBOL_TOTAL_RECORDS))
  else
    ((FAILED++))
  fi
  
done <<< "$HYPERLIQUID_SYMBOLS"

# ============================================
# Zusammenfassung
# ============================================
echo ""
echo -e "${BLUE}=========================================${NC}"
echo -e "${BLUE}Collection Summary${NC}"
echo -e "${BLUE}=========================================${NC}"
echo "Total symbols processed: $TOTAL_SYMBOLS"
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
  WHERE exchange = 'hyperliquid'
"

echo ""
echo -e "${YELLOW}Records per day (last 10 days):${NC}"
wrangler d1 execute "$DB_NAME" --remote --command "
  SELECT 
    date(collected_at/1000, 'unixepoch') as date,
    COUNT(*) as records,
    COUNT(DISTINCT symbol) as symbols
  FROM unified_funding_rates
  WHERE exchange = 'hyperliquid'
  GROUP BY date(collected_at/1000, 'unixepoch')
  ORDER BY date DESC
  LIMIT 10
"

echo ""
echo -e "${GREEN}✓ Collection complete!${NC}"