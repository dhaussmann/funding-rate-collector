/**
 * Sammelt historische Paradex Funding Daten und aggregiert sie zu Stunden-Werten
 *
 * API: https://api.prod.paradex.trade/v1/funding/data
 * - 100 Einträge pro Page (alle 5 Sekunden = 500 Sekunden Daten)
 * - Pagination über 'next' Cursor
 * - Felder: funding_rate, funding_index, funding_premium, created_at
 */

import Database from 'better-sqlite3';
import { ParadexHourlyAverage } from './src/types';

interface ParadexFundingDataPoint {
  created_at: number; // Unix timestamp in seconds
  funding_rate: string;
  funding_index: string;
  funding_premium: string;
  market: string;
}

interface ParadexFundingDataResponse {
  results: ParadexFundingDataPoint[];
  next?: string; // Pagination cursor
}

// Konfiguration
const DB_PATH = './.wrangler/state/v3/d1/miniflare-D1DatabaseObject/3331930c-2862-4372-b05a-b06c573d871f.sqlite';
const MARKETS = ['BTC-USD-PERP', 'ETH-USD-PERP', 'SOL-USD-PERP']; // Erweitern nach Bedarf
const START_DATE = '2025-01-01T00:00:00Z'; // Start-Datum
const END_DATE = new Date().toISOString(); // Bis jetzt

// Konvertiere ISO zu Unix timestamp (Sekunden)
const startTimestamp = Math.floor(new Date(START_DATE).getTime() / 1000);
const endTimestamp = Math.floor(new Date(END_DATE).getTime() / 1000);

console.log(`📊 Paradex Historical Data Collection`);
console.log(`   Markets: ${MARKETS.join(', ')}`);
console.log(`   Period: ${START_DATE} → ${END_DATE}`);
console.log(`   Start: ${startTimestamp}, End: ${endTimestamp}\n`);

/**
 * Hole alle Daten für einen Market mit Pagination
 */
async function fetchAllDataForMarket(market: string): Promise<ParadexFundingDataPoint[]> {
  const allData: ParadexFundingDataPoint[] = [];
  let nextCursor: string | undefined;
  let pageCount = 0;

  do {
    const url = new URL('https://api.prod.paradex.trade/v1/funding/data');
    url.searchParams.set('market', market);
    url.searchParams.set('start_at', startTimestamp.toString());
    url.searchParams.set('end_at', endTimestamp.toString());

    if (nextCursor) {
      url.searchParams.set('next', nextCursor);
    }

    console.log(`   Fetching page ${pageCount + 1}...`);

    const response = await fetch(url.toString(), {
      headers: { 'Accept': 'application/json' },
    });

    if (!response.ok) {
      throw new Error(`API returned ${response.status}: ${await response.text()}`);
    }

    const data: ParadexFundingDataResponse = await response.json();

    allData.push(...data.results);
    nextCursor = data.next;
    pageCount++;

    console.log(`   → Got ${data.results.length} records (total: ${allData.length})`);

    // Rate limiting: 100ms Pause zwischen Requests
    if (nextCursor) {
      await new Promise(resolve => setTimeout(resolve, 100));
    }

  } while (nextCursor);

  console.log(`   ✅ Fetched ${allData.length} data points across ${pageCount} pages\n`);
  return allData;
}

/**
 * Aggregiere 5-Sekunden-Daten zu Stunden-Werten
 */
function aggregateToHourly(
  market: string,
  dataPoints: ParadexFundingDataPoint[]
): ParadexHourlyAverage[] {

  // Gruppiere nach Stunde
  const hourlyGroups = new Map<number, ParadexFundingDataPoint[]>();

  for (const point of dataPoints) {
    // Runde auf volle Stunde ab (in Millisekunden)
    const hourTimestamp = Math.floor(point.created_at / 3600) * 3600 * 1000;

    if (!hourlyGroups.has(hourTimestamp)) {
      hourlyGroups.set(hourTimestamp, []);
    }
    hourlyGroups.get(hourTimestamp)!.push(point);
  }

  // Berechne Aggregationen
  const hourlyAverages: ParadexHourlyAverage[] = [];
  const baseAsset = market.split('-')[0];

  for (const [hourTimestamp, points] of hourlyGroups.entries()) {
    if (points.length === 0) continue;

    const fundingRates = points.map(p => parseFloat(p.funding_rate));
    const fundingPremiums = points.map(p => parseFloat(p.funding_premium));
    const fundingIndices = points.map(p => parseFloat(p.funding_index));

    // Durchschnitte
    const avgFundingRate = fundingRates.reduce((a, b) => a + b, 0) / fundingRates.length;
    const avgFundingPremium = fundingPremiums.reduce((a, b) => a + b, 0) / fundingPremiums.length;

    // Funding Index Delta: Differenz zwischen letztem und erstem Wert der Stunde
    const fundingIndexStart = Math.min(...fundingIndices);
    const fundingIndexEnd = Math.max(...fundingIndices);
    const fundingIndexDelta = fundingIndexEnd - fundingIndexStart;

    hourlyAverages.push({
      symbol: market,
      base_asset: baseAsset,
      hour_timestamp: hourTimestamp,
      avg_funding_rate: avgFundingRate,
      avg_funding_premium: avgFundingPremium,
      avg_mark_price: 0, // Nicht in API vorhanden
      avg_underlying_price: null,
      funding_index_start: fundingIndexStart,
      funding_index_end: fundingIndexEnd,
      funding_index_delta: fundingIndexDelta,
      sample_count: points.length,
    });
  }

  return hourlyAverages.sort((a, b) => a.hour_timestamp - b.hour_timestamp);
}

/**
 * Speichere in lokale D1 Datenbank
 */
function saveToDatabase(hourlyData: ParadexHourlyAverage[]) {
  const db = new Database(DB_PATH);

  const stmt = db.prepare(`
    INSERT INTO paradex_hourly_averages (
      symbol, base_asset, hour_timestamp,
      avg_funding_rate, avg_funding_premium, avg_mark_price, avg_underlying_price,
      funding_index_start, funding_index_end, funding_index_delta,
      sample_count
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ON CONFLICT(symbol, hour_timestamp) DO UPDATE SET
      avg_funding_rate = excluded.avg_funding_rate,
      avg_funding_premium = excluded.avg_funding_premium,
      funding_index_start = excluded.funding_index_start,
      funding_index_end = excluded.funding_index_end,
      funding_index_delta = excluded.funding_index_delta,
      sample_count = excluded.sample_count
  `);

  const transaction = db.transaction((data: ParadexHourlyAverage[]) => {
    for (const record of data) {
      stmt.run(
        record.symbol,
        record.base_asset,
        record.hour_timestamp,
        record.avg_funding_rate,
        record.avg_funding_premium,
        record.avg_mark_price,
        record.avg_underlying_price,
        record.funding_index_start,
        record.funding_index_end,
        record.funding_index_delta,
        record.sample_count
      );
    }
  });

  transaction(hourlyData);
  db.close();

  console.log(`   ✅ Saved ${hourlyData.length} hourly records to database\n`);
}

/**
 * Hauptfunktion
 */
async function main() {
  try {
    for (const market of MARKETS) {
      console.log(`🔄 Processing ${market}...`);

      // 1. Hole alle Daten
      const rawData = await fetchAllDataForMarket(market);

      if (rawData.length === 0) {
        console.log(`   ⚠️  No data found for ${market}\n`);
        continue;
      }

      // 2. Aggregiere zu Stunden
      console.log(`   Aggregating to hourly values...`);
      const hourlyData = aggregateToHourly(market, rawData);
      console.log(`   → Created ${hourlyData.length} hourly records`);
      console.log(`   → Time range: ${new Date(hourlyData[0].hour_timestamp).toISOString()} → ${new Date(hourlyData[hourlyData.length - 1].hour_timestamp).toISOString()}`);

      // 3. Speichere in DB
      saveToDatabase(hourlyData);

      // Zeige Beispiel
      const sample = hourlyData[0];
      console.log(`   📊 Example (first hour):`);
      console.log(`      Funding Index Delta: ${sample.funding_index_delta.toFixed(8)}`);
      console.log(`      Avg Funding Rate: ${(sample.avg_funding_rate * 100).toFixed(6)}%`);
      console.log(`      Samples: ${sample.sample_count}\n`);
    }

    console.log('✅ Historical data collection completed!\n');
    console.log('📈 Next steps:');
    console.log('   1. Verify data: SELECT COUNT(*) FROM paradex_hourly_averages;');
    console.log('   2. Deploy: npx wrangler deploy');
    console.log('   3. Check API: /paradex/hourly?symbol=BTC\n');

  } catch (error) {
    console.error('❌ Error:', error);
    process.exit(1);
  }
}

main();
