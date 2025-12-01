#!/bin/bash

DB_NAME="funding-rates-db"

echo "╔════════════════════════════════════════════════════════╗"
echo "║          Database Statistics (REMOTE)                  ║"
echo "╚════════════════════════════════════════════════════════╝"
echo ""

echo "📊 Records per Exchange:"
wrangler d1 execute "$DB_NAME" --remote --command "
  SELECT 
    exchange,
    COUNT(*) as records,
    COUNT(DISTINCT symbol) as unique_symbols
  FROM unified_funding_rates 
  GROUP BY exchange
  ORDER BY exchange
"

echo ""
echo "📅 Time Coverage:"
wrangler d1 execute "$DB_NAME" --remote --command "
  SELECT 
    exchange,
    datetime(MIN(collected_at)/1000, 'unixepoch') as earliest,
    datetime(MAX(collected_at)/1000, 'unixepoch') as latest
  FROM unified_funding_rates 
  GROUP BY exchange
  ORDER BY exchange
"

echo ""
echo "📈 Total:"
wrangler d1 execute "$DB_NAME" --remote --command "
  SELECT 
    COUNT(*) as total_records,
    COUNT(DISTINCT symbol) as unique_symbols,
    COUNT(DISTINCT exchange) as exchanges
  FROM unified_funding_rates
"
