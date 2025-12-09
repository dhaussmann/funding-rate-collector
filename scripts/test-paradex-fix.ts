/**
 * Test-Skript zur Verifizierung der Paradex Funding Rate Berechnung
 *
 * Testet die korrigierte fundingPremium Berechnung gegen echte API-Daten
 */

interface ParadexMarket {
  symbol: string;
  mark_price: string;
  funding_rate: string;
}

async function testParadexCalculation() {
  console.log('=== Paradex Funding Rate Calculation Test ===\n');

  // 1. Hole echte API-Daten
  const response = await fetch('https://api.prod.paradex.trade/v1/markets/summary?market=ALL');
  const data = await response.json();

  // Finde BTC-USD-PERP
  const btcMarket = data.results.find((m: ParadexMarket) => m.symbol === 'BTC-USD-PERP');

  if (!btcMarket) {
    console.error('BTC-USD-PERP nicht gefunden!');
    return;
  }

  console.log('API-Daten für BTC-USD-PERP:');
  console.log('  symbol:', btcMarket.symbol);
  console.log('  mark_price:', btcMarket.mark_price);
  console.log('  funding_rate:', btcMarket.funding_rate);
  console.log('');

  // 2. ALTE (falsche) Berechnung
  const fundingRate = parseFloat(btcMarket.funding_rate);
  const markPrice = parseFloat(btcMarket.mark_price);

  console.log('--- ALTE (FALSCHE) Berechnung ---');
  const oldFundingPremium = fundingRate * markPrice;
  console.log('  fundingPremium (alt):', oldFundingPremium);

  // Simuliere Integration über 1 Stunde (60 Minuten à 60 Sekunden)
  const oldFundingIndexDelta = oldFundingPremium * (3600 / 28800); // 3600s = 1h, 28800s = 8h
  console.log('  funding_index_delta (1h):', oldFundingIndexDelta);

  const oldFundingRatePercent = oldFundingIndexDelta * 100;
  const oldAnnualizedRate = oldFundingIndexDelta * 100 * 24 * 365;
  console.log('  funding_rate_percent:', oldFundingRatePercent.toFixed(10), '%');
  console.log('  annualized_rate:', oldAnnualizedRate.toFixed(2), '%');
  console.log('');

  // 3. NEUE (korrekte) Berechnung
  console.log('--- NEUE (KORREKTE) Berechnung ---');
  const newFundingPremium = fundingRate; // KEINE Multiplikation mit markPrice!
  console.log('  fundingPremium (neu):', newFundingPremium);

  // Simuliere Integration über 1 Stunde
  const newFundingIndexDelta = newFundingPremium * (3600 / 28800);
  console.log('  funding_index_delta (1h):', newFundingIndexDelta);

  const newFundingRatePercent = newFundingIndexDelta * 100;
  const newAnnualizedRate = newFundingIndexDelta * 100 * 24 * 365;
  console.log('  funding_rate_percent:', newFundingRatePercent.toFixed(10), '%');
  console.log('  annualized_rate:', newAnnualizedRate.toFixed(2), '%');
  console.log('');

  // 4. Erwartete Werte (8h rate → 1h rate)
  console.log('--- ERWARTETE WERTE ---');
  const expected1hRate = fundingRate / 8; // 8h rate → 1h rate
  const expected1hRatePercent = expected1hRate * 100;
  const expectedAnnualizedRate = expected1hRate * 100 * 24 * 365;
  console.log('  Erwartete 1h rate:', expected1hRate);
  console.log('  Erwartete funding_rate_percent:', expected1hRatePercent.toFixed(10), '%');
  console.log('  Erwartete annualized_rate:', expectedAnnualizedRate.toFixed(2), '%');
  console.log('');

  // 5. Vergleich
  console.log('--- VERGLEICH ---');
  const isCorrect = Math.abs(newFundingIndexDelta - expected1hRate) < 0.0000001;
  console.log('  Neue Berechnung korrekt?', isCorrect ? '✅ JA' : '❌ NEIN');

  if (!isCorrect) {
    console.log('  Abweichung:', Math.abs(newFundingIndexDelta - expected1hRate));
  }

  // 6. Teste auch andere Märkte
  console.log('\n=== Test weiterer Märkte ===\n');
  const perpMarkets = data.results.filter((m: ParadexMarket) =>
    m.symbol.endsWith('-PERP') && m.funding_rate
  );

  console.log('Anzahl PERP-Märkte:', perpMarkets.length);
  console.log('\nBeispiele:');

  for (let i = 0; i < Math.min(5, perpMarkets.length); i++) {
    const market = perpMarkets[i];
    const fr = parseFloat(market.funding_rate);
    const rate1h = fr / 8;
    const ratePercent = rate1h * 100;

    console.log(`  ${market.symbol.padEnd(20)} | 8h: ${(fr * 100).toFixed(4)}% | 1h: ${ratePercent.toFixed(6)}%`);
  }
}

testParadexCalculation().catch(console.error);
