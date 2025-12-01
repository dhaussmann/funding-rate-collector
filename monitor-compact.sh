#!/bin/bash

DB_NAME="funding-rates-db"

while true; do
  clear
  echo "╔════════════════════════════════════════╗"
  echo "║   DB Monitor - $(date '+%H:%M:%S')        ║"
  echo "╚════════════════════════════════════════╝"
  
  wrangler d1 execute "$DB_NAME" --remote --command "
    SELECT 
      CASE exchange
        WHEN 'hyperliquid' THEN '🔷 Hyperliquid'
        WHEN 'lighter' THEN '🔶 Lighter   '
        WHEN 'aster' THEN '⭐ Aster     '
        ELSE exchange
      END as Exchange,
      printf('%,d', COUNT(*)) as Records,
      COUNT(DISTINCT symbol) as Symbols
    FROM unified_funding_rates 
    GROUP BY exchange
    ORDER BY exchange
  " 2>/dev/null
  
  echo ""
  echo "Total: $(wrangler d1 execute "$DB_NAME" --remote --command "SELECT printf('%,d', COUNT(*)) FROM unified_funding_rates" 2>/dev/null | tail -1)"
  
  sleep 5
done
