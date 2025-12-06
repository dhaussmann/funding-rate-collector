import { Env, UnifiedFundingRate, ParadexOriginal, CollectionResult } from '../types';

export async function collectCurrentParadex(env: Env): Promise<CollectionResult> {
  try {
    console.log('[Paradex] Starting collection...');

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
    const original: ParadexOriginal[] = [];
    const now = Date.now();

    for (const market of data.results) {
      try {
        // Symbol format: "BTC-USD-PERP", "ETH-USD-PERP", etc.
        const symbol = market.symbol;
        if (!symbol || !market.funding_rate) {
          continue;
        }

        // Only collect perpetual contracts, skip options (e.g., "BTC-USD-96000-C")
        if (!symbol.endsWith('-PERP')) {
          continue;
        }

        // Extract base asset from symbol (e.g., "BTC-USD-PERP" -> "BTC")
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

        // Paradex uses 8-hour funding (3 times per day)
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

    console.log(`[Paradex] Collected ${unified.length} funding rates`);
    return { unified, original };
  } catch (error) {
    console.error('[Paradex] Collection failed:', error);
    throw error;
  }
}

export async function collectHistoricalParadex(
  env: Env,
  symbol: string,
  startTime: number,
  endTime: number
): Promise<CollectionResult> {
  // Paradex doesn't provide historical funding rate API in the current documentation
  // This function is a placeholder for future implementation
  console.log('[Paradex] Historical collection not yet implemented');
  return { unified: [], original: [] };
}
