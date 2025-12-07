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
 * Sammelt minütliche Paradex Funding Daten über WebSocket
 */
export async function collectParadexMinute(env: Env): Promise<ParadexMinuteData[]> {
  return new Promise((resolve, reject) => {
    try {
      console.log('[Paradex] Starting WebSocket collection...');

      const ws = new WebSocket('wss://ws.api.prod.paradex.trade/v1');
      const collectedData: Map<string, ParadexMinuteData> = new Map();
      const timeout = 30000; // 30 Sekunden Timeout
      let timeoutId: NodeJS.Timeout;

      // Cleanup Funktion
      const cleanup = () => {
        clearTimeout(timeoutId);
        if (ws.readyState === WebSocket.OPEN || ws.readyState === WebSocket.CONNECTING) {
          ws.close();
        }
      };

      // Timeout Handler
      timeoutId = setTimeout(() => {
        console.log('[Paradex] WebSocket timeout, closing connection');
        cleanup();
        if (collectedData.size > 0) {
          resolve(Array.from(collectedData.values()));
        } else {
          reject(new Error('WebSocket timeout - no data collected'));
        }
      }, timeout);

      // WebSocket Open Handler
      ws.addEventListener('open', () => {
        console.log('[Paradex] WebSocket connected');

        // Subscribe zu funding_data für alle Markets
        const subscribeMessage = {
          jsonrpc: '2.0',
          method: 'subscribe',
          params: {
            channel: 'funding_data',
            market_symbol: 'ALL',
          },
          id: 1,
        };

        ws.send(JSON.stringify(subscribeMessage));
        console.log('[Paradex] Subscribed to funding_data channel');
      });

      // WebSocket Message Handler
      ws.addEventListener('message', (event: MessageEvent) => {
        try {
          const message: ParadexWSMessage = JSON.parse(event.data as string);

          // Subscription Bestätigung
          if (message.id === 1 && message.jsonrpc === '2.0') {
            console.log('[Paradex] Subscription confirmed');
            return;
          }

          // Funding Data Nachrichten
          if (
            message.method === 'subscription' &&
            message.params?.channel === 'funding_data' &&
            message.params.data
          ) {
            const data = message.params.data;
            const market = data.market;

            // Nur Perpetual Contracts (Format: "BTC-USD", nicht "BTC-USD-PERP")
            // Paradex WS sendet market als "BTC-USD", nicht "BTC-USD-PERP"
            if (!market || market.includes('-')) {
              const parts = market.split('-');
              if (parts.length >= 2) {
                const baseAsset = parts[0];
                const symbol = `${market}-PERP`;

                const fundingData: ParadexMinuteData = {
                  symbol: symbol,
                  base_asset: baseAsset,
                  funding_rate: parseFloat(data.funding_rate),
                  funding_index: parseFloat(data.funding_index),
                  funding_premium: parseFloat(data.funding_premium),
                  mark_price: data.mark_price ? parseFloat(data.mark_price) : 0,
                  underlying_price: data.underlying_price ? parseFloat(data.underlying_price) : null,
                  collected_at: data.created_at * 1000, // Convert to milliseconds
                };

                collectedData.set(market, fundingData);
                console.log(`[Paradex] Collected data for ${symbol} (${collectedData.size} total)`);
              }
            }

            // Beende nach genug Daten (z.B. 50 markets oder 10 Sekunden)
            if (collectedData.size >= 50) {
              console.log(`[Paradex] Collected ${collectedData.size} markets, closing connection`);
              cleanup();
              resolve(Array.from(collectedData.values()));
            }
          }
        } catch (err) {
          console.error('[Paradex] Error parsing WebSocket message:', err);
        }
      });

      // WebSocket Error Handler
      ws.addEventListener('error', (event: Event) => {
        console.error('[Paradex] WebSocket error:', event);
        cleanup();
        reject(new Error('WebSocket connection error'));
      });

      // WebSocket Close Handler
      ws.addEventListener('close', (event: CloseEvent) => {
        console.log(`[Paradex] WebSocket closed: ${event.code} ${event.reason}`);
        cleanup();

        if (collectedData.size > 0) {
          resolve(Array.from(collectedData.values()));
        } else if (!timeoutId) {
          // Timeout hat bereits resolved/rejected
          return;
        } else {
          reject(new Error('WebSocket closed without collecting data'));
        }
      });
    } catch (error) {
      console.error('[Paradex] Collection failed:', error);
      reject(error);
    }
  });
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
