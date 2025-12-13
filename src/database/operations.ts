import {
  Env,
  UnifiedFundingRate,
  HyperliquidOriginal,
  LighterOriginal,
  AsterOriginal,
  BinanceOriginal,
  ParadexOriginal,
  ParadexMinuteData,
  ParadexHourlyAverage,
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

    case 'paradex':
      stmt = env.DB.prepare(`
        INSERT INTO paradex_funding_history (symbol, base_asset, funding_rate, mark_price, last_traded_price, collected_at)
        VALUES (?, ?, ?, ?, ?, ?)
      `);
      batch = original.map((o: ParadexOriginal) =>
        stmt.bind(
          o.symbol,
          o.base_asset,
          o.funding_rate,
          o.mark_price,
          o.last_traded_price,
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

/**
 * Speichert minütliche Paradex Daten
 */
export async function saveParadexMinuteData(env: Env, data: ParadexMinuteData[]): Promise<void> {
  if (data.length === 0) return;

  try {
    const stmt = env.DB.prepare(`
      INSERT INTO paradex_minute_data (
        symbol, base_asset, funding_rate, funding_index, funding_premium,
        mark_price, underlying_price, collected_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    `);

    const batch = data.map((d) =>
      stmt.bind(
        d.symbol,
        d.base_asset,
        d.funding_rate,
        d.funding_index,
        d.funding_premium,
        d.mark_price,
        d.underlying_price,
        d.collected_at
      )
    );

    await env.DB.batch(batch);
    console.log(`[DB] Saved ${data.length} Paradex minute data records`);
  } catch (error) {
    console.error('[DB] Failed to save Paradex minute data:', error);
    throw error;
  }
}

/**
 * Speichert stündliche Paradex Aggregationen
 */
export async function saveParadexHourlyAverages(env: Env, data: ParadexHourlyAverage[]): Promise<void> {
  if (data.length === 0) return;

  try {
    const stmt = env.DB.prepare(`
      INSERT INTO paradex_hourly_averages (
        symbol, base_asset, hour_timestamp,
        avg_funding_rate, avg_funding_premium, avg_mark_price, avg_underlying_price,
        funding_index_start, funding_index_end, funding_index_delta,
        sample_count
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(symbol, hour_timestamp) DO UPDATE SET
        avg_funding_rate = excluded.avg_funding_rate,
        avg_funding_premium = excluded.avg_funding_premium,
        avg_mark_price = excluded.avg_mark_price,
        avg_underlying_price = excluded.avg_underlying_price,
        funding_index_start = excluded.funding_index_start,
        funding_index_end = excluded.funding_index_end,
        funding_index_delta = excluded.funding_index_delta,
        sample_count = excluded.sample_count
    `);

    const batch = data.map((d) =>
      stmt.bind(
        d.symbol,
        d.base_asset,
        d.hour_timestamp,
        d.avg_funding_rate,
        d.avg_funding_premium,
        d.avg_mark_price,
        d.avg_underlying_price,
        d.funding_index_start,
        d.funding_index_end,
        d.funding_index_delta,
        d.sample_count
      )
    );

    await env.DB.batch(batch);
    console.log(`[DB] Saved ${data.length} Paradex hourly average records`);
  } catch (error) {
    console.error('[DB] Failed to save Paradex hourly averages:', error);
    throw error;
  }
}

/**
 * Speichert Spot-Market-Daten (nur exchange + symbol)
 * Löscht zuerst alle alten Daten der Börse, dann fügt die aktuellen ein
 */
export async function saveSpotMarkets(
  env: Env,
  exchange: string,
  markets: any[]
): Promise<void> {
  if (markets.length === 0) return;

  try {
    // 1. Lösche alle alten Daten für diese Börse
    await env.DB.prepare('DELETE FROM unified_spot_markets WHERE exchange = ?')
      .bind(exchange)
      .run();

    // 2. Füge neue Daten ein
    const stmt = env.DB.prepare(`
      INSERT INTO unified_spot_markets (exchange, symbol, collected_at)
      VALUES (?, ?, ?)
    `);

    const batch = markets.map((market: any) =>
      stmt.bind(market.exchange, market.symbol, market.collectedAt)
    );

    await env.DB.batch(batch);
    console.log(`[DB] Replaced spot market data for ${exchange}: ${markets.length} markets`);
  } catch (error) {
    console.error(`[DB] Failed to save spot market data for ${exchange}:`, error);
    throw error;
  }
}