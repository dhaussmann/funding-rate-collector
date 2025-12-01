// src/collectors/lighter.ts
import { Env, UnifiedFundingRate } from '../types';

interface LighterMarket {
  market_id: number;
  symbol: string;
  status: string;
}

interface LighterFunding {
  rate: number;      // WICHTIG: Bereits in PROZENT! (z.B. 0.0012 = 0.0012%)
  direction: 'long' | 'short';
  timestamp: number; // in SECONDS!
}

// CURRENT Collection
export async function collectCurrentLighter(env: Env): Promise<{
  unified: UnifiedFundingRate[];
  original: any[];
}> {
  const unified: UnifiedFundingRate[] = [];
  const original: any[] = [];

  try {
    // Hole alle aktiven Markets
    const marketsResponse = await fetch('https://mainnet.zklighter.elliot.ai/api/v1/orderBooks');
    
    if (!marketsResponse.ok) {
      throw new Error(`Lighter markets API error: ${marketsResponse.status}`);
    }

    const marketsData = await marketsResponse.json();
    const activeMarkets: LighterMarket[] = marketsData.order_books.filter(
      (m: LighterMarket) => m.status === 'active'
    );

    // Hole aktuelle Funding Rates für jeden Market
    const endTimestamp = Math.floor(Date.now() / 1000); // Sekunden!
    const startTimestamp = endTimestamp - 7200; // Letzte 2 Stunden

    for (const market of activeMarkets) {
      try {
        const fundingUrl = `https://mainnet.zklighter.elliot.ai/api/v1/fundings?market_id=${market.market_id}&resolution=1h&start_timestamp=${startTimestamp}&end_timestamp=${endTimestamp}&count_back=0`;
        const fundingResponse = await fetch(fundingUrl);
        
        if (!fundingResponse.ok) {
          console.warn(`[Lighter] Failed to fetch funding for ${market.symbol}: ${fundingResponse.status}`);
          continue;
        }

        const fundingData = await fundingResponse.json();

        if (fundingData.fundings && fundingData.fundings.length > 0) {
          // Nehme die neueste Funding Rate
          const funding: LighterFunding = fundingData.fundings[fundingData.fundings.length - 1];

          // WICHTIG: Lighter API gibt rate bereits in PROZENT zurück!
          // Beispiel: rate: 0.0012 bedeutet 0.0012% (nicht 0.12%)
          
          // Vorzeichen basierend auf Direction
          const ratePercent = funding.direction === 'short' ? -funding.rate : funding.rate;
          
          // Konvertiere zu Dezimal für fundingRate Feld
          const fundingRate = ratePercent / 100;  // 0.0012 / 100 = 0.000012

          // Annualisierung (stündlich * 24 * 365)
          const annualizedRate = ratePercent * 24 * 365;  // 0.0012 * 24 * 365 = 10.512%

          // Original Daten speichern
          original.push({
            market_id: market.market_id,
            symbol: market.symbol,
            rate: funding.rate,
            direction: funding.direction,
            timestamp: funding.timestamp,
          });

          // Unified Format
          unified.push({
            exchange: 'lighter',
            symbol: market.symbol,
            tradingPair: market.symbol,
            fundingRate: fundingRate,               // Dezimal: 0.000012
            fundingRatePercent: ratePercent,        // Prozent: 0.0012
            annualizedRate: annualizedRate,         // Annualisiert: 10.512
            collectedAt: funding.timestamp * 1000,  // Konvertiere Sekunden zu Millisekunden
          });
        }
      } catch (error) {
        console.error(`[Lighter] Error fetching funding for market ${market.symbol}:`, error);
      }
    }

    console.log(`[Lighter] Collected ${unified.length} funding rates`);
  } catch (error) {
    console.error('[Lighter] Error collecting rates:', error);
    throw error;
  }

  return { unified, original };
}

// HISTORICAL Collection
export async function collectHistoricalLighter(
  env: Env,
  symbol: string,
  startTime: number,
  endTime: number
): Promise<{
  unified: UnifiedFundingRate[];
  original: any[];
}> {
  const unified: UnifiedFundingRate[] = [];
  const original: any[] = [];

  try {
    // Hole alle Markets und finde die market_id für das Symbol
    const marketsResponse = await fetch('https://mainnet.zklighter.elliot.ai/api/v1/orderBooks');
    const marketsData = await marketsResponse.json();
    
    const market = marketsData.order_books.find((m: LighterMarket) => m.symbol === symbol);
    
    if (!market) {
      throw new Error(`Market not found for symbol: ${symbol}`);
    }

    // Konvertiere timestamps zu Sekunden
    const startTimestamp = Math.floor(startTime / 1000);
    const endTimestamp = Math.floor(endTime / 1000);

    const fundingUrl = `https://mainnet.zklighter.elliot.ai/api/v1/fundings?market_id=${market.market_id}&resolution=1h&start_timestamp=${startTimestamp}&end_timestamp=${endTimestamp}&count_back=0`;
    const fundingResponse = await fetch(fundingUrl);
    const fundingData = await fundingResponse.json();

    if (fundingData.fundings) {
      for (const funding of fundingData.fundings) {
        const ratePercent = funding.direction === 'short' ? -funding.rate : funding.rate;
        const fundingRate = ratePercent / 100;
        const annualizedRate = ratePercent * 24 * 365;

        original.push({
          market_id: market.market_id,
          symbol: market.symbol,
          rate: funding.rate,
          direction: funding.direction,
          timestamp: funding.timestamp,
        });

        unified.push({
          exchange: 'lighter',
          symbol: market.symbol,
          tradingPair: market.symbol,
          fundingRate: fundingRate,
          fundingRatePercent: ratePercent,
          annualizedRate: annualizedRate,
          collectedAt: funding.timestamp * 1000,
        });
      }
    }

    console.log(`[Lighter] Collected ${unified.length} historical funding rates for ${symbol}`);
  } catch (error) {
    console.error('[Lighter] Error collecting historical rates:', error);
    throw error;
  }

  return { unified, original };
}