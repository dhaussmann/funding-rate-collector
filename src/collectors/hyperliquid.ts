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
  markets: SpotMarket[];
}> {
  const markets: SpotMarket[] = [];

  try {
    // 1. Hole zuerst alle Perpetual-Token-Namen
    const perpResponse = await fetch('https://api.hyperliquid.xyz/info', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ type: 'metaAndAssetCtxs' }),
    });

    if (!perpResponse.ok) {
      throw new Error(`Hyperliquid Perp API error: ${perpResponse.status}`);
    }

    const perpData = await perpResponse.json();
    const perpMeta: HyperliquidMeta = perpData[0];

    // Erstelle Set mit allen Perp-Token-Namen (ohne delisted)
    const perpTokenNames = new Set<string>(
      perpMeta.universe
        .filter(t => !t.isDelisted)
        .map(t => t.name)
    );

    console.log(`[Hyperliquid Spot] Found ${perpTokenNames.size} perpetual tokens`);

    // 2. Hole Spot-Metadaten
    const spotResponse = await fetch('https://api.hyperliquid.xyz/info', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ type: 'spotMeta' }),
    });

    if (!spotResponse.ok) {
      throw new Error(`Hyperliquid Spot API error: ${spotResponse.status}`);
    }

    const data: HyperliquidSpotMeta = await spotResponse.json();
    const collectedAt = Date.now();

    // 3. Verarbeite alle Spot-Tokens mit intelligenter Namensbereinigung
    for (const token of data.tokens) {
      let symbolName = token.name;

      // Wenn Token mit "U" beginnt, prüfe ob es eine Perp-Version ohne "U" gibt
      if (token.name.startsWith('U') && token.name.length > 1) {
        const nameWithoutU = token.name.substring(1); // Entferne "U" am Anfang

        // Wenn es einen Perp mit diesem Namen gibt, verwende den Namen ohne "U"
        if (perpTokenNames.has(nameWithoutU)) {
          symbolName = nameWithoutU;
          console.log(`[Hyperliquid Spot] Mapping ${token.name} → ${symbolName} (Perp exists)`);
        }
        // Sonst behalte den Namen mit "U" (z.B. UNIT, USDC bleiben so)
      }

      // Nur exchange + symbol speichern
      markets.push({
        exchange: 'hyperliquid',
        symbol: symbolName,  // Bereinigter Name (z.B. BTC statt UBTC)
        collectedAt,
      });
    }

    console.log(`[Hyperliquid Spot] Collected ${markets.length} spot markets`);
  } catch (error) {
    console.error('[Hyperliquid Spot] Error collecting markets:', error);
    throw error;
  }

  return { markets };
}