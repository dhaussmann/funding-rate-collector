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

export interface ParadexMinuteData {
  symbol: string;
  base_asset: string;
  funding_rate: number;
  funding_index: number;
  funding_premium: number;
  mark_price: number;
  underlying_price: number | null;
  collected_at: number;
}

export interface ParadexHourlyAverage {
  symbol: string;
  base_asset: string;
  hour_timestamp: number;
  avg_funding_rate: number;
  avg_funding_premium: number;
  avg_mark_price: number;
  avg_underlying_price: number | null;
  funding_index_start: number;
  funding_index_end: number;
  funding_index_delta: number;
  sample_count: number;
}

export interface CollectionResult {
  unified: UnifiedFundingRate[];
  original: any[];
}
