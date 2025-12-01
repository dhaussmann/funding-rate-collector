import { Env, UnifiedFundingRate, AsterOriginal, CollectionResult } from '../types';

export async function collectCurrentAster(env: Env): Promise<CollectionResult> {
  try {
    const exchangeResponse = await fetch('https://fapi.asterdex.com/fapi/v1/exchangeInfo');
    const exchangeData = await exchangeResponse.json();

    const activeSymbols = exchangeData.symbols.filter(
      (s: any) =>
        s.contractType === 'PERPETUAL' && s.status === 'TRADING' && s.symbol.endsWith('USDT')
    );

    const unified: UnifiedFundingRate[] = [];
    const original: AsterOriginal[] = [];
    const now = Date.now();

    for (const symbolObj of activeSymbols) {
      try {
        const fundingResponse = await fetch(
          `https://fapi.asterdex.com/fapi/v1/fundingRate?symbol=${symbolObj.symbol}&limit=1`
        );
        const fundingData = await fundingResponse.json();

        if (fundingData && fundingData.length > 0) {
          const latest = fundingData[0];
          const rate = parseFloat(latest.fundingRate);

          original.push({
            symbol: symbolObj.symbol,
            base_asset: symbolObj.baseAsset,
            funding_rate: rate,
            funding_time: latest.fundingTime,
            collected_at: now,
          });

          unified.push({
            exchange: 'aster',
            symbol: symbolObj.baseAsset,
            tradingPair: symbolObj.symbol,
            fundingRate: rate,
            fundingRatePercent: rate * 100,
            annualizedRate: rate * 100 * 3 * 365,
            collectedAt: now,
          });
        }
      } catch (err) {
        console.error(`[Aster] Failed for ${symbolObj.symbol}:`, err);
      }
    }

    return { unified, original };
  } catch (error) {
    console.error('[Aster] Collection failed:', error);
    throw error;
  }
}

export async function collectHistoricalAster(
  env: Env,
  symbol: string,
  startTime: number,
  endTime: number
): Promise<CollectionResult> {
  try {
    const exchangeResponse = await fetch('https://fapi.asterdex.com/fapi/v1/exchangeInfo');
    const exchangeData = await exchangeResponse.json();

    const symbolObj = exchangeData.symbols.find(
      (s: any) =>
        s.contractType === 'PERPETUAL' && s.status === 'TRADING' && s.baseAsset === symbol
    );

    if (!symbolObj) {
      throw new Error(`Symbol ${symbol} not found on Aster`);
    }

    const tradingPair = symbolObj.symbol;
    const unified: UnifiedFundingRate[] = [];
    const original: AsterOriginal[] = [];

    let currentStart = startTime;

    while (currentStart < endTime) {
      const response = await fetch(
        `https://aster.wirewaving.workers.dev?symbol=${tradingPair}&startTime=${currentStart}&endTime=${endTime}&limit=1000`
      );
      const data = await response.json();

      if (!data || data.length === 0) break;

      for (const item of data) {
        const rate = parseFloat(item.fundingRate);
        const fundingTime = item.fundingTime;

        original.push({
          symbol: tradingPair,
          base_asset: symbol,
          funding_rate: rate,
          funding_time: fundingTime,
          collected_at: fundingTime,
        });

        unified.push({
          exchange: 'aster',
          symbol: symbol,
          tradingPair: tradingPair,
          fundingRate: rate,
          fundingRatePercent: rate * 100,
          annualizedRate: rate * 100 * 3 * 365,
          collectedAt: fundingTime,
        });
      }

      currentStart = data[data.length - 1].fundingTime + 1;
      await new Promise((resolve) => setTimeout(resolve, 100));
    }

    return { unified, original };
  } catch (error) {
    console.error(`[Aster] Historical collection failed for ${symbol}:`, error);
    throw error;
  }
}
