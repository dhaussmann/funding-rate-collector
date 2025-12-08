#!/bin/bash

# ============================================
# Paradex Historical - Parallel Collection
# ============================================
# Nutzt API Rate Limit optimal:
# - Limit: 1500 req/min = 25 req/s
# - Strategy: 5 Workers à 5 req/s = 25 req/s
# ============================================

# Konfiguration
NUM_WORKERS=5
START_TIME=1735689600000  # 2025-01-01 00:00:00 UTC
END_TIME=$(date +%s)000   # Jetzt

# Farben
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}=========================================${NC}"
echo -e "${BLUE}Paradex Historical - Parallel Collection${NC}"
echo -e "${BLUE}=========================================${NC}"
echo "Workers: $NUM_WORKERS"
echo "Period: $(date -d "@$((START_TIME / 1000))" '+%Y-%m-%d' 2>/dev/null || date -r $((START_TIME / 1000)) '+%Y-%m-%d') to $(date '+%Y-%m-%d')"
echo "Rate: 25 req/s total (1500 req/min - at API limit)"
echo ""

# Hole alle Markets
echo -e "${YELLOW}Fetching Paradex markets...${NC}"
MARKETS_RESPONSE=$(curl -s "https://api.prod.paradex.trade/v1/markets/summary?market=ALL")
MARKETS=$(echo "$MARKETS_RESPONSE" | jq -r '.results[] | select(.symbol | endswith("-PERP")) | .symbol' | sort -u)
TOTAL_COUNT=$(echo "$MARKETS" | wc -l | tr -d ' ')

echo -e "${GREEN}✓ Found $TOTAL_COUNT perpetual markets${NC}"
echo ""

# Teile Markets auf Worker auf
TEMP_DIR=$(mktemp -d)
MARKETS_PER_WORKER=$(( (TOTAL_COUNT + NUM_WORKERS - 1) / NUM_WORKERS ))

echo -e "${YELLOW}Splitting markets across $NUM_WORKERS workers...${NC}"
echo "$MARKETS" | split -l $MARKETS_PER_WORKER - "$TEMP_DIR/markets_"

WORKER_FILES=()
WORKER_COUNT=0
for file in "$TEMP_DIR"/markets_*; do
  ((WORKER_COUNT++))
  WORKER_FILES+=("$file")
  MARKET_COUNT=$(wc -l < "$file")
  echo "  Worker $WORKER_COUNT: $MARKET_COUNT markets"
done

echo ""
echo -e "${YELLOW}Starting $WORKER_COUNT workers in parallel...${NC}"
echo ""

# Starte alle Worker parallel
PIDS=()
for i in "${!WORKER_FILES[@]}"; do
  WORKER_ID=$((i + 1))
  ./collect-paradex-historical-worker.sh "$WORKER_ID" "${WORKER_FILES[$i]}" "$START_TIME" "$END_TIME" > "$TEMP_DIR/worker_${WORKER_ID}.log" 2>&1 &
  PIDS+=($!)
  echo "Started Worker $WORKER_ID (PID: ${PIDS[$i]})"
done

echo ""
echo -e "${YELLOW}Waiting for workers to complete...${NC}"
echo "You can monitor progress with: tail -f $TEMP_DIR/worker_*.log"
echo ""

# Warte auf alle Worker
START_EPOCH=$(date +%s)
for i in "${!PIDS[@]}"; do
  WORKER_ID=$((i + 1))
  wait ${PIDS[$i]}
  EXIT_CODE=$?

  if [ $EXIT_CODE -eq 0 ]; then
    echo -e "${GREEN}✓ Worker $WORKER_ID completed successfully${NC}"
  else
    echo -e "${RED}✗ Worker $WORKER_ID failed (exit code: $EXIT_CODE)${NC}"
  fi
done

END_EPOCH=$(date +%s)
DURATION=$((END_EPOCH - START_EPOCH))
HOURS=$((DURATION / 3600))
MINUTES=$(((DURATION % 3600) / 60))

echo ""
echo -e "${BLUE}=========================================${NC}"
echo -e "${BLUE}Collection Complete!${NC}"
echo -e "${BLUE}=========================================${NC}"
printf "Total runtime: %dh %dm\n" $HOURS $MINUTES
echo ""

# Zeige Worker Logs
echo -e "${YELLOW}Worker Summaries:${NC}"
for i in "${!WORKER_FILES[@]}"; do
  WORKER_ID=$((i + 1))
  echo ""
  echo -e "${BLUE}--- Worker $WORKER_ID ---${NC}"
  tail -5 "$TEMP_DIR/worker_${WORKER_ID}.log"
done

echo ""
echo -e "${YELLOW}Full logs available at: $TEMP_DIR/worker_*.log${NC}"
echo ""

# Optional: Cleanup
read -p "Delete worker logs? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
  rm -rf "$TEMP_DIR"
  echo "Logs deleted."
else
  echo "Logs kept at: $TEMP_DIR"
fi
