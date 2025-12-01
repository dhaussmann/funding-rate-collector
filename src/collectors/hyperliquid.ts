// src/collectors/hyperliquid.ts
import { Env, UnifiedFundingRate } from '../types';

interface HyperliquidToken {
  name: string;
  isDelisted?: boolean;
}

interface HyperliquidMeta {
  universe: HyperliquidToken[];
}

interface HyperliquidAssetContext {
  funding: string;  // Dezimal-Wert, STÜNDLICHE Rate
  markPx?: string;
  oraclePx?: string;
}

// CURRENT Collection
export async function collectCurrentHyperliquid(env: Env): Promise<{
  unified: UnifiedFundingRate[];
  original: any[];
}> {
  const unified: UnifiedFundingRate[] = [];
  const original: any[] = [];

  try {
    // Hole Meta-Daten und Asset Contexts
    const response = await fetch('https://api.hyperliquid.xyz/info', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ type: 'metaAndAssetCtxs' }),
    });

    if (!response.ok) {
      throw new Error(`Hyperliquid API error: ${response.status}`);
    }

    const data = await response.json();
    const meta: HyperliquidMeta = data[0];
    const assetContexts: HyperliquidAssetContext[] = data[1];

    const collectedAt = Date.now();

    // Hyperliquid gibt funding rate für jedes Asset zurück
    // universe Array und assetContexts Array haben gleiche Reihenfolge!
    for (let i = 0; i < meta.universe.length; i++) {
      const token = meta.universe[i];
      const ctx = assetContexts[i];

      // Skip delisted tokens
      if (token.isDelisted) continue;

      const coin = token.name;
      const fundingRate = parseFloat(ctx.funding);

      // WICHTIG: Hyperliquid gibt STÜNDLICHE Rate zurück (nicht 8h!)
      // Obwohl Payments 3x täglich sind, ist die API-Rate stündlich
      const fundingRatePercent = fundingRate * 100;
      const annualizedRate = fundingRate * 100 * 24 * 365;  // 24h statt 3x!

      // Original Daten speichern (Format für hyperliquid_funding_history Tabelle)
      original.push({
        coin: coin,
        funding: ctx.funding,  // String wert von API
        funding_rate: fundingRate, // Parsed float
        collected_at: collectedAt,
      });

      // Unified Format
      unified.push({
        exchange: 'hyperliquid',
        symbol: coin,
        tradingPair: coin,
        fundingRate,
        fundingRatePercent,
        annualizedRate,
        collectedAt,
      });
    }

    console.log(`[Hyperliquid] Collected ${unified.length} funding rates`);
  } catch (error) {
    console.error('[Hyperliquid] Error collecting rates:', error);
    throw error;
  }

  return { unified, original };
}

// HISTORICAL Collection
export async function collectHistoricalHyperliquid(
  env: Env,
  symbol: string,
  startTime: number,
  endTime: number
): Promise<{
  unified: UnifiedFundingRate[];
  original: any[];
}> {
  // Hyperliquid hat keine historische Funding Rate API
  // Wir können nur aktuelle Daten sammeln
  console.warn('[Hyperliquid] Historical data collection not supported, returning current data');
  return collectCurrentHyperliquid(env);
}