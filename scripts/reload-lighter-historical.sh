#!/bin/bash

# Script zum Neu-Laden historischer Lighter Daten
# Verwendung: ./scripts/reload-lighter-historical.sh [BASE_URL] [SYMBOL] [DAYS]

BASE_URL="${1:-http://localhost:8787}"
SYMBOL="${2:-BTC}"
DAYS="${3:-30}"

echo "🔄 Reloading Lighter historical data"
echo "====================================="
echo "URL: $BASE_URL"
echo "Symbol: $SYMBOL"
echo "Days: $DAYS"
echo ""

# Berechne Start- und Endzeit
END_TIME=$(date +%s)000  # Milliseconds
START_TIME=$((END_TIME - (DAYS * 24 * 60 * 60 * 1000)))

echo "📅 Time range:"
echo "  Start: $(date -d @$((START_TIME / 1000)) '+%Y-%m-%d %H:%M:%S')"
echo "  End:   $(date -d @$((END_TIME / 1000)) '+%Y-%m-%d %H:%M:%S')"
echo ""

# API Call
echo "🚀 Fetching historical data..."
curl -X GET "$BASE_URL/collect/historical?exchange=lighter&symbol=$SYMBOL&startTime=$START_TIME&endTime=$END_TIME" \
  -H "Content-Type: application/json" | jq '.'

echo ""
echo "✅ Done! Check the results above."
