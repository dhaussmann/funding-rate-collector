import { Env, UnifiedFundingRate, ParadexMinuteData, ParadexHourlyAverage } from '../types';

interface ParadexWSMessage {
  jsonrpc: string;
  method: string;
  params?: {
    channel: string;
    data?: {
      created_at: number;
      funding_rate: string;
      funding_premium: string;
      funding_index: string;
      market: string;
      mark_price?: string;
      underlying_price?: string;
    };
  };
  id?: number;
}

/**
 * Sammelt minütliche Paradex Funding Daten über REST API
 *
 * HINWEIS: Da Paradex funding_index nur über WebSocket bereitstellt und
 * Cloudflare Workers WebSocket-Clients in scheduled contexts nicht unterstützen,
 * verwenden wir eine Approximation:
 *
 * funding_index wird durch Integration der funding_rate über Zeit berechnet.
 * funding_premium wird aus funding_rate * 8h (da Paradex 8h rates nutzt) berechnet.
 */
export async function collectParadexMinute(env: Env): Promise<ParadexMinuteData[]> {
  try {
    console.log('[Paradex] Starting minute collection via REST API...');

    const response = await fetch('https://api.prod.paradex.trade/v1/markets/summary?market=ALL', {
      headers: {
        'Accept': 'application/json',
      },
    });

    if (!response.ok) {
      throw new Error(`Paradex API returned ${response.status}`);
    }

    const data = await response.json();

    if (!data.results || !Array.isArray(data.results)) {
      throw new Error('Unexpected API response format');
    }

    const minuteData: ParadexMinuteData[] = [];
    const now = Date.now();

    // Hole vorherigen funding_index aus der Datenbank
    const previousIndexQuery = await env.DB.prepare(`
      SELECT symbol, funding_index, collected_at
      FROM paradex_minute_data
      WHERE collected_at = (SELECT MAX(collected_at) FROM paradex_minute_data)
    `).all();

    const previousIndexMap = new Map<string, { index: number; timestamp: number }>();
    if (previousIndexQuery.results) {
      for (const row: any of previousIndexQuery.results) {
        previousIndexMap.set(row.symbol, {
          index: row.funding_index,
          timestamp: row.collected_at,
        });
      }
    }

    for (const market of data.results) {
      try {
        const symbol = market.symbol;
        if (!symbol || !market.funding_rate) {
          continue;
        }

        // Nur Perpetual Contracts
        if (!symbol.endsWith('-PERP')) {
          continue;
        }

        const baseAsset = symbol.split('-')[0];
        const fundingRate = parseFloat(market.funding_rate);
        const markPrice = parseFloat(market.mark_price || '0');
        const underlyingPrice = market.underlying_price ? parseFloat(market.underlying_price) : null;

        // FIX: funding_rate ist bereits eine prozentuale Rate (z.B. 0.00005 = 0.005%)
        // Wir speichern diese direkt als Rate, NICHT als absoluten USDC-Betrag
        // funding_premium = funding_rate (keine Multiplikation mit markPrice)
        const fundingPremium = fundingRate;

        // Berechne funding_index durch Integration
        let fundingIndex = 0;
        const previous = previousIndexMap.get(symbol);

        if (previous) {
          // Zeit-Delta in Sekunden
          const timeDelta = (now - previous.timestamp) / 1000;
          // funding_index = previous_index + funding_premium * (time_delta / 8h_in_seconds)
          // 8h = 8 * 3600 = 28800 seconds
          fundingIndex = previous.index + (fundingPremium * timeDelta / 28800);
        } else {
          // Erster Datenpunkt: Starte bei 0
          fundingIndex = 0;
        }

        minuteData.push({
          symbol: symbol,
          base_asset: baseAsset,
          funding_rate: fundingRate,
          funding_index: fundingIndex,
          funding_premium: fundingPremium,
          mark_price: markPrice,
          underlying_price: underlyingPrice,
          collected_at: now,
        });
      } catch (err) {
        console.error(`[Paradex] Failed to parse market ${market.symbol}:`, err);
      }
    }

    console.log(`[Paradex] Collected ${minuteData.length} minute data records via REST API`);
    return minuteData;
  } catch (error) {
    console.error('[Paradex] Minute collection failed:', error);
    throw error;
  }
}

/**
 * Berechnet stündliche Aggregationen aus minütlichen Daten
 */
export async function aggregateParadexHourly(env: Env): Promise<ParadexHourlyAverage[]> {
  try {
    console.log('[Paradex] Starting hourly aggregation...');

    // Aktueller Stunden-Timestamp (abgerundet auf volle Stunde)
    const now = Date.now();
    const hourTimestamp = Math.floor(now / 3600000) * 3600000;
    const startTime = hourTimestamp - 3600000; // Vor 1 Stunde

    console.log(`[Paradex] Aggregating data from ${new Date(startTime).toISOString()} to ${new Date(hourTimestamp).toISOString()}`);

    // Hole alle minütlichen Daten der letzten Stunde, gruppiert nach Symbol
    const query = `
      SELECT
        symbol,
        base_asset,
        AVG(funding_rate) as avg_funding_rate,
        AVG(funding_premium) as avg_funding_premium,
        AVG(mark_price) as avg_mark_price,
        AVG(underlying_price) as avg_underlying_price,
        MIN(funding_index) as funding_index_start,
        MAX(funding_index) as funding_index_end,
        COUNT(*) as sample_count
      FROM paradex_minute_data
      WHERE collected_at >= ? AND collected_at < ?
      GROUP BY symbol, base_asset
      HAVING sample_count >= 30
    `;

    const { results } = await env.DB.prepare(query).bind(startTime, hourTimestamp).all();

    if (!results || results.length === 0) {
      console.log('[Paradex] No data to aggregate');
      return [];
    }

    const aggregations: ParadexHourlyAverage[] = results.map((row: any) => ({
      symbol: row.symbol,
      base_asset: row.base_asset,
      hour_timestamp: hourTimestamp - 3600000, // Die Stunde, die wir aggregieren
      avg_funding_rate: row.avg_funding_rate,
      avg_funding_premium: row.avg_funding_premium,
      avg_mark_price: row.avg_mark_price,
      avg_underlying_price: row.avg_underlying_price,
      funding_index_start: row.funding_index_start,
      funding_index_end: row.funding_index_end,
      funding_index_delta: row.funding_index_end - row.funding_index_start,
      sample_count: row.sample_count,
    }));

    console.log(`[Paradex] Aggregated ${aggregations.length} symbols`);
    return aggregations;
  } catch (error) {
    console.error('[Paradex] Hourly aggregation failed:', error);
    throw error;
  }
}

/**
 * Legacy Funktion für Kompatibilität (nutzt REST API)
 */
export async function collectCurrentParadex(env: Env): Promise<{ unified: UnifiedFundingRate[], original: any[] }> {
  try {
    console.log('[Paradex] Starting legacy REST API collection...');

    const response = await fetch('https://api.prod.paradex.trade/v1/markets/summary?market=ALL', {
      headers: {
        'Accept': 'application/json',
      },
    });

    if (!response.ok) {
      throw new Error(`Paradex API returned ${response.status}`);
    }

    const data = await response.json();

    if (!data.results || !Array.isArray(data.results)) {
      throw new Error('Unexpected API response format');
    }

    const unified: UnifiedFundingRate[] = [];
    const original: any[] = [];
    const now = Date.now();

    for (const market of data.results) {
      try {
        const symbol = market.symbol;
        if (!symbol || !market.funding_rate) {
          continue;
        }

        // Nur Perpetual Contracts
        if (!symbol.endsWith('-PERP')) {
          continue;
        }

        const baseAsset = symbol.split('-')[0];
        const fundingRate = parseFloat(market.funding_rate);

        original.push({
          symbol: symbol,
          base_asset: baseAsset,
          funding_rate: fundingRate,
          mark_price: parseFloat(market.mark_price || '0'),
          last_traded_price: parseFloat(market.last_traded_price || '0'),
          collected_at: now,
        });

        unified.push({
          exchange: 'paradex',
          symbol: baseAsset,
          tradingPair: symbol,
          fundingRate: fundingRate,
          fundingRatePercent: fundingRate * 100,
          annualizedRate: fundingRate * 100 * 3 * 365,
          collectedAt: now,
        });
      } catch (err) {
        console.error(`[Paradex] Failed to parse market ${market.symbol}:`, err);
      }
    }

    console.log(`[Paradex] Collected ${unified.length} funding rates via REST API`);
    return { unified, original };
  } catch (error) {
    console.error('[Paradex] Legacy collection failed:', error);
    throw error;
  }
}

export async function collectHistoricalParadex(
  env: Env,
  symbol: string,
  startTime: number,
  endTime: number
): Promise<{ unified: UnifiedFundingRate[], original: any[] }> {
  console.log('[Paradex] Historical collection not yet implemented');
  return { unified: [], original: [] };
}
