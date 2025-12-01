#!/bin/bash

# batch_collect.sh - Sammle historische Daten für alle Tokens

WORKER_URL="https://your-worker.workers.dev"
START_TIME=$(date -d "2024-01-01" +%s)000
END_TIME=$(date -d "2024-12-31" +%s)000

SYMBOLS=("BTC" "ETH" "SOL" "AVAX" "MATIC" "ARB" "OP")
EXCHANGES=("binance" "aster" "lighter")

for EXCHANGE in "${EXCHANGES[@]}"; do
  for SYMBOL in "${SYMBOLS[@]}"; do
    echo "Collecting $EXCHANGE - $SYMBOL..."
    
    curl -X GET "$WORKER_URL/collect/historical?exchange=$EXCHANGE&symbol=$SYMBOL&startTime=$START_TIME&endTime=$END_TIME"
    
    echo ""
    sleep 2  # Rate limiting
  done
done

echo "Historical collection completed!"