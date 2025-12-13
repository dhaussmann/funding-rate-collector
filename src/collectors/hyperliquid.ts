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

// Spot Market Interfaces
interface HyperliquidSpotToken {
  name: string;
  szDecimals: number;
  weiDecimals: number;
  index: number;
  tokenId: string;
  isCanonical: boolean;
}

interface HyperliquidSpotMeta {
  tokens: HyperliquidSpotToken[];
  universe: Array<{
    tokens: number[];  // indices in tokens array
    name: string;
    index: number;
    isCanonical: boolean;
  }>;
}

export interface SpotMarket {
  exchange: string;
  symbol: string;
  baseAsset?: string;
  quoteAsset?: string;
  status: string;
  collectedAt: number;
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

// SPOT MARKETS Collection
export async function collectSpotMarketsHyperliquid(env: Env): Promise<{
  unified: SpotMarket[];
  original: any[];
}> {
  const unified: SpotMarket[] = [];
  const original: any[] = [];

  try {
    // Hole Spot-Metadaten
    const response = await fetch('https://api.hyperliquid.xyz/info', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ type: 'spotMeta' }),
    });

    if (!response.ok) {
      throw new Error(`Hyperliquid Spot API error: ${response.status}`);
    }

    const data: HyperliquidSpotMeta = await response.json();
    const collectedAt = Date.now();

    // Verarbeite alle Spot-Tokens
    for (const token of data.tokens) {
      // Original Daten speichern (für hyperliquid_spot_markets Tabelle)
      original.push({
        token_name: token.name,
        token_id: token.tokenId,
        sz_decimals: token.szDecimals,
        wei_decimals: token.weiDecimals,
        is_canonical: token.isCanonical ? 1 : 0,
        collected_at: collectedAt,
      });

      // Unified Format
      unified.push({
        exchange: 'hyperliquid',
        symbol: token.name,
        baseAsset: token.name,
        quoteAsset: 'USDC',  // Hyperliquid Spot ist USDC-basiert
        status: 'active',
        collectedAt,
      });
    }

    console.log(`[Hyperliquid Spot] Collected ${unified.length} spot markets`);
  } catch (error) {
    console.error('[Hyperliquid Spot] Error collecting markets:', error);
    throw error;
  }

  return { unified, original };
}