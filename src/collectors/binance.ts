import { Env, UnifiedFundingRate, BinanceOriginal, CollectionResult } from '../types';

// WICHTIG: Nur Top-Symbole sammeln, um Rate Limits zu vermeiden
const TOP_SYMBOLS = [
  'BTCUSDT', 'ETHUSDT', 'BNBUSDT', 'SOLUSDT', 'XRPUSDT',
  'ADAUSDT', 'DOGEUSDT', 'AVAXUSDT', 'DOTUSDT', 'MATICUSDT',
  'LINKUSDT', 'UNIUSDT', 'ATOMUSDT', 'LTCUSDT', 'ETCUSDT',
  'NEARUSDT', 'APTUSDT', 'ARBUSDT', 'OPUSDT', 'INJUSDT'
];

export async function collectCurrentBinance(env: Env): Promise<CollectionResult> {
  try {
    console.log('[Binance] Starting collection...');
    
    const exchangeResponse = await fetch('https://fapi.binance.com/fapi/v1/exchangeInfo');
    
    if (!exchangeResponse.ok) {
      throw new Error(`Binance API returned ${exchangeResponse.status}`);
    }
    
    const exchangeData = await exchangeResponse.json();

    // Filtere nur Top-Symbole
    const activeSymbols = exchangeData.symbols.filter(
      (s: any) =>
        s.contractType === 'PERPETUAL' && 
        s.status === 'TRADING' && 
        TOP_SYMBOLS.includes(s.symbol)
    );

    console.log(`[Binance] Found ${activeSymbols.length} active symbols`);

    const unified: UnifiedFundingRate[] = [];
    const original: BinanceOriginal[] = [];
    const now = Date.now();

    // Batch-Request: Hole alle Funding Rates auf einmal
    for (const symbolObj of activeSymbols) {
      try {
        const fundingResponse = await fetch(
          `https://fapi.binance.com/fapi/v1/fundingRate?symbol=${symbolObj.symbol}&limit=1`
        );

        if (!fundingResponse.ok) {
          console.error(`[Binance] Failed for ${symbolObj.symbol}: ${fundingResponse.status}`);
          continue;
        }

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
            exchange: 'binance',
            symbol: symbolObj.baseAsset,
            tradingPair: symbolObj.symbol,
            fundingRate: rate,
            fundingRatePercent: rate * 100,
            annualizedRate: rate * 100 * 3 * 365,
            collectedAt: now,
          });
        }

        // Rate limiting: 100ms Pause zwischen Requests
        await new Promise(resolve => setTimeout(resolve, 100));
      } catch (err) {
        console.error(`[Binance] Failed for ${symbolObj.symbol}:`, err);
      }
    }

    console.log(`[Binance] Collected ${unified.length} funding rates`);
    return { unified, original };
  } catch (error) {
    console.error('[Binance] Collection failed:', error);
    throw error;
  }
}

export async function collectHistoricalBinance(
  env: Env,
  symbol: string,
  startTime: number,
  endTime: number
): Promise<CollectionResult> {
  try {
    const exchangeResponse = await fetch('https://fapi.binance.com/fapi/v1/exchangeInfo');
    const exchangeData = await exchangeResponse.json();

    const symbolObj = exchangeData.symbols.find(
      (s: any) =>
        s.contractType === 'PERPETUAL' && s.status === 'TRADING' && s.baseAsset === symbol
    );

    if (!symbolObj) {
      throw new Error(`Symbol ${symbol} not found on Binance`);
    }

    const tradingPair = symbolObj.symbol;
    const unified: UnifiedFundingRate[] = [];
    const original: BinanceOriginal[] = [];

    let currentStart = startTime;

    while (currentStart < endTime) {
      const response = await fetch(
        `https://fapi.binance.com/fapi/v1/fundingRate?symbol=${tradingPair}&startTime=${currentStart}&endTime=${endTime}&limit=1000`
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
          exchange: 'binance',
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
    console.error(`[Binance] Historical collection failed for ${symbol}:`, error);
    throw error;
  }
}