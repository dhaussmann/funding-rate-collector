#!/bin/bash

# Einfacher Wrapper zum Starten der Collection mit automatischem Monitoring

echo "Starting Paradex collection in background..."
./collect-paradex-recent.sh &
COLLECTION_PID=$!

echo "Collection PID: $COLLECTION_PID"
echo ""

# Warte kurz bis Logs erstellt werden
sleep 3

# Prüfe ob Log-Dir existiert
LOG_DIR=$(find ./logs -maxdepth 1 -type d -name "paradex-recent-*" 2>/dev/null | sort -r | head -1)

if [ -n "$LOG_DIR" ]; then
  echo "Logs: $LOG_DIR"
  echo ""
  echo "Monitoring Commands:"
  echo "  Live monitor:  ./monitor-paradex-collection.sh"
  echo "  Quick status:  ./status-paradex-collection.sh"
  echo "  Follow logs:   tail -f $LOG_DIR/worker_*.log"
  echo ""
  echo "Starting live monitor in 5 seconds..."
  sleep 5
  ./monitor-paradex-collection.sh
else
  echo "Warning: No log directory created yet"
  echo "Wait a few seconds and run: ./monitor-paradex-collection.sh"
fi
