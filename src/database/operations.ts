import {
  Env,
  UnifiedFundingRate,
  HyperliquidOriginal,
  LighterOriginal,
  AsterOriginal,
  BinanceOriginal,
} from '../types';

export async function saveToDBCurrent(
  env: Env,
  exchange: string,
  unified: UnifiedFundingRate[],
  original: any[]
): Promise<void> {
  if (unified.length === 0) return;

  try {
    await saveOriginalData(env, exchange, original);
    await saveUnifiedData(env, unified);
    console.log(`[DB] Saved ${unified.length} records for ${exchange}`);
  } catch (error) {
    console.error(`[DB] Failed to save data for ${exchange}:`, error);
    throw error;
  }
}

async function saveOriginalData(env: Env, exchange: string, original: any[]): Promise<void> {
  if (original.length === 0) return;

  let stmt;
  let batch;

  switch (exchange) {
    case 'hyperliquid':
      stmt = env.DB.prepare(`
        INSERT INTO hyperliquid_funding_history (coin, funding_rate, collected_at)
        VALUES (?, ?, ?)
      `);
      batch = original.map((o: any) =>
        stmt.bind(
          o.coin,
          parseFloat(o.funding) || 0, // funding statt funding_rate
          o.collected_at || Date.now()
        )
      );
      break;

    case 'lighter':
      stmt = env.DB.prepare(`
        INSERT INTO lighter_funding_history (market_id, symbol, timestamp, rate, direction, collected_at)
        VALUES (?, ?, ?, ?, ?, ?)
      `);
      batch = original.map((o: LighterOriginal) =>
        stmt.bind(
          o.market_id,
          o.symbol,
          o.timestamp,
          o.rate,
          o.direction,
          o.collected_at || Date.now()
        )
      );
      break;

    case 'aster':
      stmt = env.DB.prepare(`
        INSERT INTO aster_funding_history (symbol, base_asset, funding_rate, funding_time, collected_at)
        VALUES (?, ?, ?, ?, ?)
      `);
      batch = original.map((o: AsterOriginal) =>
        stmt.bind(
          o.symbol,
          o.base_asset,
          o.funding_rate,
          o.funding_time,
          o.collected_at || Date.now()
        )
      );
      break;

    case 'binance':
      stmt = env.DB.prepare(`
        INSERT INTO binance_funding_history (symbol, base_asset, funding_rate, funding_time, collected_at)
        VALUES (?, ?, ?, ?, ?)
      `);
      batch = original.map((o: BinanceOriginal) =>
        stmt.bind(
          o.symbol,
          o.base_asset,
          o.funding_rate,
          o.funding_time,
          o.collected_at || Date.now()
        )
      );
      break;

    default:
      throw new Error(`Unknown exchange: ${exchange}`);
  }

  await env.DB.batch(batch);
}

async function saveUnifiedData(env: Env, unified: UnifiedFundingRate[]): Promise<void> {
  const stmt = env.DB.prepare(`
    INSERT INTO unified_funding_rates (
      exchange, symbol, trading_pair, funding_rate,
      funding_rate_percent, annualized_rate, collected_at
    ) VALUES (?, ?, ?, ?, ?, ?, ?)
  `);

  const batch = unified.map((rate) =>
    stmt.bind(
      rate.exchange,
      rate.symbol,
      rate.tradingPair || rate.symbol, // Fallback falls tradingPair undefined
      rate.fundingRate,
      rate.fundingRatePercent,
      rate.annualizedRate,
      rate.collectedAt
    )
  );

  await env.DB.batch(batch);
}