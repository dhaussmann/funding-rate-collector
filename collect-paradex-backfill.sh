#!/bin/bash

# ============================================
# Paradex Backfill - Iterative Historical Collection
# ============================================
# Strategy: Find oldest data, collect 30 days before
# Run multiple times until reaching 2025-01-01
# ============================================

# Konfiguration
NUM_WORKERS=5
TARGET_START=1735689600000  # 2025-01-01 00:00:00 - Don't go before this
DB_NAME="funding-rates-db"

# Farben
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}=========================================${NC}"
echo -e "${BLUE}Paradex Historical Backfill${NC}"
echo -e "${BLUE}Iterative 30-Day Collection${NC}"
echo -e "${BLUE}=========================================${NC}"
echo ""

# Finde ältesten Eintrag in der Datenbank
echo -e "${YELLOW}Checking oldest data in database...${NC}"

OLDEST_TIMESTAMP=$(wrangler d1 execute "$DB_NAME" --remote --command "
  SELECT MIN(collected_at) as oldest
  FROM unified_funding_rates
  WHERE exchange = 'paradex'
" --json | jq -r '.[0].results[0].oldest // empty')

if [ -z "$OLDEST_TIMESTAMP" ] || [ "$OLDEST_TIMESTAMP" = "null" ]; then
  echo -e "${RED}✗ No Paradex data found in database!${NC}"
  echo -e "${YELLOW}Please run ./collect-paradex-recent.sh first${NC}"
  exit 1
fi

OLDEST_DATE=$(date -d "@$((OLDEST_TIMESTAMP / 1000))" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date -r $((OLDEST_TIMESTAMP / 1000)) '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "Unknown")
TARGET_DATE=$(date -d "@$((TARGET_START / 1000))" '+%Y-%m-%d' 2>/dev/null || date -r $((TARGET_START / 1000)) '+%Y-%m-%d' 2>/dev/null || echo "Unknown")

echo -e "${GREEN}✓ Oldest data: $OLDEST_DATE${NC}"
echo -e "  Target: $TARGET_DATE"
echo ""

# Prüfe ob wir schon beim Ziel sind
if [ "$OLDEST_TIMESTAMP" -le "$TARGET_START" ]; then
  echo -e "${GREEN}✓ Already have data back to target date!${NC}"
  echo -e "${GREEN}✓ Historical collection complete!${NC}"
  exit 0
fi

# Berechne neuen Zeitraum: 30 Tage vor dem ältesten Eintrag
END_TIME=$OLDEST_TIMESTAMP
START_TIME=$((END_TIME - 30 * 24 * 3600 * 1000))  # -30 days

# Stelle sicher, dass wir nicht vor dem Target-Datum sammeln
if [ "$START_TIME" -lt "$TARGET_START" ]; then
  START_TIME=$TARGET_START
  echo -e "${YELLOW}⚠ Adjusted start time to target date${NC}"
fi

START_DATE=$(date -d "@$((START_TIME / 1000))" '+%Y-%m-%d' 2>/dev/null || date -r $((START_TIME / 1000)) '+%Y-%m-%d' 2>/dev/null || echo "Unknown")
END_DATE=$(date -d "@$((END_TIME / 1000))" '+%Y-%m-%d' 2>/dev/null || date -r $((END_TIME / 1000)) '+%Y-%m-%d' 2>/dev/null || echo "Unknown")

DAYS=$(( (END_TIME - START_TIME) / 86400000 ))

echo -e "${BLUE}Next collection period:${NC}"
echo "  From: $START_DATE"
echo "  To:   $END_DATE"
echo "  Days: $DAYS"
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
echo "Monitor progress: tail -f $TEMP_DIR/worker_*.log"
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
echo -e "${BLUE}Backfill Iteration Complete!${NC}"
echo -e "${BLUE}=========================================${NC}"
printf "Runtime: %dh %dm\n" $HOURS $MINUTES
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

# Cleanup
rm -rf "$TEMP_DIR"

# Prüfe ob wir fertig sind
NEW_OLDEST=$(wrangler d1 execute "$DB_NAME" --remote --command "
  SELECT MIN(collected_at) as oldest
  FROM unified_funding_rates
  WHERE exchange = 'paradex'
" --json | jq -r '.[0].results[0].oldest // empty')

if [ "$NEW_OLDEST" -le "$TARGET_START" ]; then
  echo -e "${GREEN}=========================================${NC}"
  echo -e "${GREEN}✓ COMPLETE! Reached target date!${NC}"
  echo -e "${GREEN}=========================================${NC}"
  NEW_OLDEST_DATE=$(date -d "@$((NEW_OLDEST / 1000))" '+%Y-%m-%d' 2>/dev/null || date -r $((NEW_OLDEST / 1000)) '+%Y-%m-%d' 2>/dev/null || echo "Unknown")
  echo "Oldest data now: $NEW_OLDEST_DATE"
  echo ""
  echo -e "${GREEN}All historical data collected!${NC}"
else
  NEW_OLDEST_DATE=$(date -d "@$((NEW_OLDEST / 1000))" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date -r $((NEW_OLDEST / 1000)) '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "Unknown")
  DAYS_REMAINING=$(( (NEW_OLDEST - TARGET_START) / 86400000 ))
  ITERATIONS_REMAINING=$(( (DAYS_REMAINING + 29) / 30 ))

  echo -e "${YELLOW}=========================================${NC}"
  echo -e "${YELLOW}More data to collect${NC}"
  echo -e "${YELLOW}=========================================${NC}"
  echo "Current oldest: $NEW_OLDEST_DATE"
  echo "Days remaining: ~$DAYS_REMAINING"
  echo "Estimated iterations: ~$ITERATIONS_REMAINING"
  echo ""
  echo -e "${YELLOW}Run this script again to collect next 30 days:${NC}"
  echo "  ./collect-paradex-backfill.sh"
fi
