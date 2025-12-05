export interface Env {
  DB: D1Database;
}

export interface UnifiedFundingRate {
  exchange: 'hyperliquid' | 'lighter' | 'aster' | 'binance' | 'paradex';
  symbol: string;
  tradingPair: string;
  fundingRate: number;
  fundingRatePercent: number;
  annualizedRate: number;
  collectedAt: number;
}

export interface HyperliquidOriginal {
  coin: string;
  funding_rate: number;
  collected_at: number;
}

export interface LighterOriginal {
  market_id: number;
  symbol: string;
  timestamp: number;
  rate: number;
  direction: string;
  collected_at: number;
}

export interface AsterOriginal {
  symbol: string;
  base_asset: string;
  funding_rate: number;
  funding_time: number;
  collected_at: number;
}

export interface BinanceOriginal {
  symbol: string;
  base_asset: string;
  funding_rate: number;
  funding_time: number;
  collected_at: number;
}

export interface ParadexOriginal {
  symbol: string;
  base_asset: string;
  funding_rate: number;
  mark_price: number;
  last_traded_price: number;
  collected_at: number;
}

export interface CollectionResult {
  unified: UnifiedFundingRate[];
  original: any[];
}
