#!/bin/bash

# Test-Script für Paradex Integration
# Stelle sicher, dass der Dev-Server läuft: npm run dev

BASE_URL="${1:-http://localhost:8787}"

echo "🧪 Testing Paradex Integration"
echo "================================"
echo ""

# Test 1: Health Check
echo "1️⃣  Health Check..."
curl -s "$BASE_URL/health" | jq '.'
echo ""

# Test 2: Manuelle Collection triggern (inkl. Paradex)
echo "2️⃣  Triggering manual collection (including Paradex)..."
curl -s -X POST "$BASE_URL/collect" | jq '.'
echo ""

# Test 3: Neueste Paradex Rates abrufen
echo "3️⃣  Getting latest Paradex rates..."
curl -s "$BASE_URL/rates?exchange=paradex&limit=10" | jq '.'
echo ""

# Test 4: Paradex BTC Rates
echo "4️⃣  Getting Paradex BTC rates..."
curl -s "$BASE_URL/rates?exchange=paradex&symbol=BTC&limit=5" | jq '.'
echo ""

# Test 5: Vergleich über alle Exchanges für BTC
echo "5️⃣  Comparing BTC funding rates across all exchanges..."
curl -s "$BASE_URL/compare?symbol=BTC" | jq '.'
echo ""

# Test 6: Stats
echo "6️⃣  Getting collection statistics..."
curl -s "$BASE_URL/stats" | jq '.'
echo ""

echo "✅ Tests abgeschlossen!"
