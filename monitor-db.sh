#!/bin/bash

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}=== Database Live Monitor ===${NC}"
echo "Press Ctrl+C to stop"
echo ""

LAST_TOTAL=0

while true; do
  clear
  echo -e "${BLUE}=== $(date '+%Y-%m-%d %H:%M:%S') ===${NC}"
  echo ""
  
  # Gesamtanzahl
  CURRENT_TOTAL=$(wrangler d1 execute funding-rates-db --command "SELECT COUNT(*) as count FROM unified_funding_rates" 2>/dev/null | grep -oE '[0-9]+' | tail -1)
  
  if [ ! -z "$CURRENT_TOTAL" ]; then
    DIFF=$((CURRENT_TOTAL - LAST_TOTAL))
    
    if [ $DIFF -gt 0 ]; then
      echo -e "${GREEN}Total Records: $CURRENT_TOTAL (+$DIFF)${NC}"
    else
      echo -e "${YELLOW}Total Records: $CURRENT_TOTAL${NC}"
    fi
    
    LAST_TOTAL=$CURRENT_TOTAL
  fi
  
  echo ""
  echo -e "${BLUE}By Exchange:${NC}"
  wrangler d1 execute funding-rates-db --command "
    SELECT 
      exchange,
      COUNT(*) as records,
      COUNT(DISTINCT symbol) as symbols,
      datetime(MAX(collected_at)/1000, 'unixepoch') as latest
    FROM unified_funding_rates 
    GROUP BY exchange
    ORDER BY exchange
  " 2>/dev/null
  
  echo ""
  echo -e "${BLUE}Recent Inserts (last 10):${NC}"
  wrangler d1 execute funding-rates-db --command "
    SELECT 
      exchange,
      symbol,
      datetime(collected_at/1000, 'unixepoch') as time
    FROM unified_funding_rates 
    ORDER BY collected_at DESC 
    LIMIT 10
  " 2>/dev/null
  
  sleep 3
done
