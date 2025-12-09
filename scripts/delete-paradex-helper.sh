#!/bin/bash

# Hilfsskript zum sicheren Löschen der fehlerhaften Paradex-Daten

echo "=== Paradex Data Cleanup Helper ==="
echo ""
echo "Dieses Skript hilft beim Löschen der fehlerhaften Paradex-Daten von heute."
echo ""

# Aktuelles Datum ermitteln (kompatibel mit BSD und GNU date)
if date -v 1d > /dev/null 2>&1; then
  # BSD date (macOS)
  TODAY=$(date -u +%Y-%m-%d)
  START_OF_DAY=$(date -u -j -f "%Y-%m-%d %H:%M:%S" "$TODAY 00:00:00" +%s)000
  END_OF_DAY=$(date -u -j -f "%Y-%m-%d %H:%M:%S" "$TODAY 23:59:59" +%s)999
  START_FORMATTED=$(date -u -j -f %s $((START_OF_DAY/1000)) '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "$TODAY 00:00:00")
  END_FORMATTED=$(date -u -j -f %s $((END_OF_DAY/1000)) '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "$TODAY 23:59:59")
else
  # GNU date (Linux)
  TODAY=$(date -u +%Y-%m-%d)
  START_OF_DAY=$(date -u -d "$TODAY 00:00:00" +%s)000
  END_OF_DAY=$(date -u -d "$TODAY 23:59:59" +%s)999
  START_FORMATTED=$(date -u -d @$((START_OF_DAY/1000)) '+%Y-%m-%d %H:%M:%S')
  END_FORMATTED=$(date -u -d @$((END_OF_DAY/1000)) '+%Y-%m-%d %H:%M:%S')
fi

echo "Heutiges Datum (UTC): $TODAY"
echo ""
echo "Zeitbereich:"
echo "  Start: $START_OF_DAY ($START_FORMATTED)"
echo "  Ende:  $END_OF_DAY ($END_FORMATTED)"
echo ""

# Schritt 1: Prüfe, wie viele Einträge betroffen sind
echo "=== Schritt 1: Prüfe betroffene Einträge ==="
echo ""

echo "Checking unified_funding_rates..."
npx wrangler d1 execute funding-rates-db --remote --command \
  "SELECT COUNT(*) as count FROM unified_funding_rates WHERE exchange = 'paradex' AND collected_at >= $START_OF_DAY AND collected_at <= $END_OF_DAY"

echo ""
echo "Checking paradex_minute_data..."
npx wrangler d1 execute funding-rates-db --remote --command \
  "SELECT COUNT(*) as count FROM paradex_minute_data WHERE collected_at >= $START_OF_DAY AND collected_at <= $END_OF_DAY"

echo ""
echo "Checking paradex_hourly_averages..."
npx wrangler d1 execute funding-rates-db --remote --command \
  "SELECT COUNT(*) as count FROM paradex_hourly_averages WHERE hour_timestamp >= $START_OF_DAY AND hour_timestamp <= $END_OF_DAY"

echo ""
echo "=== Schritt 2: Bestätigung ==="
echo ""
read -p "Möchtest du diese Einträge WIRKLICH löschen? (yes/no): " confirmation

if [ "$confirmation" != "yes" ]; then
  echo "Abgebrochen."
  exit 0
fi

echo ""
echo "=== Schritt 3: Lösche Daten ==="
echo ""

echo "Deleting from unified_funding_rates..."
npx wrangler d1 execute funding-rates-db --remote --command \
  "DELETE FROM unified_funding_rates WHERE exchange = 'paradex' AND collected_at >= $START_OF_DAY AND collected_at <= $END_OF_DAY"

echo "Deleting from paradex_minute_data..."
npx wrangler d1 execute funding-rates-db --remote --command \
  "DELETE FROM paradex_minute_data WHERE collected_at >= $START_OF_DAY AND collected_at <= $END_OF_DAY"

echo "Deleting from paradex_hourly_averages..."
npx wrangler d1 execute funding-rates-db --remote --command \
  "DELETE FROM paradex_hourly_averages WHERE hour_timestamp >= $START_OF_DAY AND hour_timestamp <= $END_OF_DAY"

echo ""
echo "=== Fertig! ==="
echo "Die fehlerhaften Daten wurden gelöscht."
