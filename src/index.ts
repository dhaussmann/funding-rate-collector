import { Env, UnifiedFundingRate } from './types';
import {
  collectCurrentHyperliquid,
  collectCurrentLighter,
  collectCurrentAster,
  collectCurrentParadex,
  collectHistoricalAster,
  collectHistoricalLighter,
  collectHistoricalHyperliquid,
  collectHistoricalParadex,
} from './collectors';
import { collectParadexMinute, aggregateParadexHourly } from './collectors/paradex';
import { collectSpotMarketsHyperliquid } from './collectors/hyperliquid';
import { collectSpotMarketsLighter } from './collectors/lighter';
import { saveToDBCurrent, saveParadexMinuteData, saveParadexHourlyAverages, saveSpotMarkets } from './database/operations';

export default {
  async scheduled(event: ScheduledEvent, env: Env, ctx: ExecutionContext): Promise<void> {
    const startTime = Date.now();
    const now = new Date();
    const currentMinute = now.getUTCMinutes();

    try {
      // ===== MINÜTLICH: Paradex Datensammlung =====
      console.log('[CRON] Starting Paradex minute collection...');
      try {
        const paradexMinuteData = await collectParadexMinute(env);
        if (paradexMinuteData.length > 0) {
          await saveParadexMinuteData(env, paradexMinuteData);
          console.log(`[CRON] Paradex minute: Saved ${paradexMinuteData.length} records`);
        }
      } catch (error) {
        console.error('[CRON] Paradex minute collection failed:', error);
      }

      // ===== STÜNDLICH (Minute 1): Andere Exchanges + Paradex Aggregation =====
      if (currentMinute === 1) {
        console.log('[CRON] Starting hourly tasks (other exchanges + Paradex aggregation)...');

        // 1. Andere Exchanges sammeln
        const results = await Promise.allSettled([
          collectCurrentHyperliquid(env),
          collectCurrentLighter(env),
          collectCurrentAster(env),
          collectCurrentParadex(env), // Legacy REST API Collection
        ]);

        const stats = {
          hyperliquid: 0,
          lighter: 0,
          aster: 0,
          paradex_legacy: 0,
          paradex_hourly: 0,
          errors: [] as string[],
        };

        for (let i = 0; i < results.length; i++) {
          const result = results[i];
          const exchangeName = ['hyperliquid', 'lighter', 'aster', 'paradex'][i];

          if (result.status === 'fulfilled') {
            const { unified, original } = result.value;
            stats[exchangeName as keyof typeof stats] = unified.length;
            await saveToDBCurrent(env, exchangeName, unified, original);
          } else {
            const error = `${exchangeName}: ${result.reason}`;
            stats.errors.push(error);
            console.error(`[CRON] ${error}`);
          }
        }

        // 2. Paradex Stündliche Aggregation
        try {
          const paradexHourly = await aggregateParadexHourly(env);
          if (paradexHourly.length > 0) {
            await saveParadexHourlyAverages(env, paradexHourly);
            stats.paradex_hourly = paradexHourly.length;
            console.log(`[CRON] Paradex hourly: Aggregated ${paradexHourly.length} symbols`);

            // Speichere auch in unified_funding_rates für /compare Endpoint
            const unifiedFromHourly: UnifiedFundingRate[] = paradexHourly.map((h) => ({
              exchange: 'paradex',
              symbol: h.base_asset,
              tradingPair: h.symbol,
              fundingRate: h.funding_index_delta, // Verwende 1h delta statt 8h rate
              fundingRatePercent: h.funding_index_delta * 100,
              annualizedRate: h.funding_index_delta * 100 * 24 * 365, // 1h rate → annualisiert
              collectedAt: h.hour_timestamp,
            }));

            // Update unified_funding_rates mit besseren Daten
            const stmt = env.DB.prepare(`
              INSERT INTO unified_funding_rates (
                exchange, symbol, trading_pair, funding_rate,
                funding_rate_percent, annualized_rate, collected_at
              ) VALUES (?, ?, ?, ?, ?, ?, ?)
            `);

            const batch = unifiedFromHourly.map((rate) =>
              stmt.bind(
                rate.exchange,
                rate.symbol,
                rate.tradingPair,
                rate.fundingRate,
                rate.fundingRatePercent,
                rate.annualizedRate,
                rate.collectedAt
              )
            );

            await env.DB.batch(batch);
            console.log(`[CRON] Updated unified_funding_rates with ${unifiedFromHourly.length} Paradex hourly records`);
          }
        } catch (error) {
          console.error('[CRON] Paradex hourly aggregation failed:', error);
          stats.errors.push(`paradex_hourly: ${error}`);
        }

        const duration = Date.now() - startTime;
        console.log('[CRON] Hourly tasks completed:', { ...stats, duration: `${duration}ms` });
      }

      // ===== TÄGLICH (Stunde 0, Minute 0): Spot Markets sammeln =====
      const currentHour = now.getUTCHours();
      if (currentHour === 0 && currentMinute === 0) {
        console.log('[CRON] Starting daily spot markets collection...');

        const spotResults = await Promise.allSettled([
          collectSpotMarketsHyperliquid(env),
          collectSpotMarketsLighter(env),
        ]);

        const spotStats = {
          hyperliquid_spot: 0,
          lighter_spot: 0,
          errors: [] as string[],
        };

        for (let i = 0; i < spotResults.length; i++) {
          const result = spotResults[i];
          const exchangeName = ['hyperliquid', 'lighter'][i];

          if (result.status === 'fulfilled') {
            const { unified, original } = result.value;
            spotStats[`${exchangeName}_spot` as keyof typeof spotStats] = unified.length;
            await saveSpotMarkets(env, exchangeName, unified, original);
          } else {
            const error = `${exchangeName}_spot: ${result.reason}`;
            spotStats.errors.push(error);
            console.error(`[CRON] ${error}`);
          }
        }

        const spotDuration = Date.now() - startTime;
        console.log('[CRON] Daily spot markets collection completed:', { ...spotStats, duration: `${spotDuration}ms` });
      }

      const totalDuration = Date.now() - startTime;
      console.log(`[CRON] All tasks completed in ${totalDuration}ms`);
    } catch (error) {
      console.error('[CRON] Fatal error:', error);
      throw error;
    }
  },

  async fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    const url = new URL(request.url);
    const path = url.pathname;

    const corsHeaders = {
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type',
    };

    if (request.method === 'OPTIONS') {
      return new Response(null, { headers: corsHeaders });
    }

    try {
      if (path === '/' || path === '') {
        return new Response(
          'Funding Rate Collector API\n\n' +
          'General Endpoints:\n' +
          '- /health\n' +
          '- /collect\n' +
          '- /rates\n' +
          '- /compare?symbol=BTC\n' +
          '- /history?symbol=HYPE&hours=24\n' +
          '- /debug?symbol=HYPE\n' +
          '- /stats\n' +
          '\nParadex Specific Endpoints:\n' +
          '- /paradex/hourly?symbol=BTC&hours=24\n' +
          '- /paradex/minute?symbol=BTC&minutes=60\n' +
          '\nSpot Markets Endpoints:\n' +
          '- /spot-markets?exchange=hyperliquid\n' +
          '- /spot-markets/collect',
          {
            headers: { ...corsHeaders, 'Content-Type': 'text/plain' },
          }
        );
      }

      if (path === '/health') {
        return new Response(JSON.stringify({ status: 'ok', timestamp: Date.now() }), {
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        });
      }

      if (path === '/collect') {
        console.log('[API] Manual collection triggered');

        const results = await Promise.allSettled([
          collectCurrentHyperliquid(env),
          collectCurrentLighter(env),
          collectCurrentAster(env),
          collectCurrentParadex(env),
        ]);

        const stats = {
          hyperliquid: 0,
          lighter: 0,
          aster: 0,
          paradex: 0,
          errors: [] as string[],
        };

        const exchanges = ['hyperliquid', 'lighter', 'aster', 'paradex'];

        for (let i = 0; i < results.length; i++) {
          const result = results[i];
          const exchangeName = exchanges[i];

          if (result.status === 'fulfilled') {
            const { unified, original } = result.value;
            stats[exchangeName as keyof typeof stats] = unified.length;

            if (!env.DB) {
              console.error('[DB] Database binding not found!');
              stats.errors.push(`${exchangeName}: Database not bound`);
              continue;
            }

            try {
              await saveToDBCurrent(env, exchangeName, unified, original);
              console.log(`[DB] Saved ${unified.length} records for ${exchangeName}`);
            } catch (dbError: any) {
              console.error(`[DB] Save failed for ${exchangeName}:`, dbError);
              stats.errors.push(`${exchangeName}: ${dbError.message}`);
            }
          } else {
            stats.errors.push(`${exchangeName}: ${result.reason}`);
            console.error(`[Collection] Failed for ${exchangeName}:`, result.reason);
          }
        }

        return new Response(
          JSON.stringify({
            success: stats.errors.length === 0,
            breakdown: stats,
            timestamp: Date.now(),
          }),
          {
            headers: { ...corsHeaders, 'Content-Type': 'application/json' },
          }
        );
      }

      if (path === '/rates') {
  const exchange = url.searchParams.get('exchange');
  const symbol = url.searchParams.get('symbol');
  const limit = parseInt(url.searchParams.get('limit') || '10000');

  // Hole die neuesten Daten pro Exchange/Symbol Kombination
  let query = `
    SELECT * FROM unified_funding_rates
    WHERE (exchange, symbol, collected_at) IN (
      SELECT exchange, symbol, MAX(collected_at)
      FROM unified_funding_rates
      WHERE 1=1
  `;
  
  const params: any[] = [];

  if (exchange) {
    query += ' AND exchange = ?';
    params.push(exchange);
  }
  
  if (symbol) {
    query += ' AND symbol = ?';
    params.push(symbol);
  }

  query += `
      GROUP BY exchange, symbol
    )
    ORDER BY exchange, symbol
    LIMIT ?
  `;
  
  params.push(limit);

  const { results } = await env.DB.prepare(query).bind(...params).all();

  return new Response(JSON.stringify(results), {
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

      // ============================================
      // FIXED: /compare Endpoint
      // ============================================
      if (path === '/compare') {
        const symbol = url.searchParams.get('symbol') || 'BTC';

        // NEUE QUERY: Holt für jede Börse separat die neuesten Daten
        const { results } = await env.DB.prepare(`
          SELECT exchange, symbol, funding_rate_percent, annualized_rate, collected_at
          FROM unified_funding_rates
          WHERE symbol = ?
            AND (exchange, collected_at) IN (
              SELECT exchange, MAX(collected_at)
              FROM unified_funding_rates
              WHERE symbol = ?
              GROUP BY exchange
            )
          ORDER BY exchange
        `)
          .bind(symbol, symbol)
          .all();

        return new Response(
          JSON.stringify({
            symbol,
            exchanges: results,
            timestamp: Date.now(),
          }),
          {
            headers: { ...corsHeaders, 'Content-Type': 'application/json' },
          }
        );
      }

      // ============================================
      // NEU: /history Endpoint - Letzte X Stunden
      // ============================================
      if (path === '/history') {
        const symbol = url.searchParams.get('symbol');
        const exchange = url.searchParams.get('exchange');
        const limit = parseInt(url.searchParams.get('limit') || '10000');

        // Datumsbereich-Parameter
        let startTime: number;
        let endTime: number;
        let queryMode: 'range' | 'hours' = 'hours';

        // Option 1: Unix Timestamps (Millisekunden)
        const startTimeParam = url.searchParams.get('startTime');
        const endTimeParam = url.searchParams.get('endTime');

        // Option 2: ISO8601 Datumsstrings
        const startDateParam = url.searchParams.get('startDate');
        const endDateParam = url.searchParams.get('endDate');

        // Option 3: Relative Stunden (Standard/Fallback)
        const hours = parseInt(url.searchParams.get('hours') || '24');

        if (startTimeParam && endTimeParam) {
          // Verwende absolute Unix Timestamps
          startTime = parseInt(startTimeParam);
          endTime = parseInt(endTimeParam);
          queryMode = 'range';
        } else if (startDateParam && endDateParam) {
          // Parse ISO8601 Datumsstrings
          startTime = new Date(startDateParam).getTime();
          endTime = new Date(endDateParam).getTime();
          queryMode = 'range';
        } else {
          // Fallback: Relative Stunden
          startTime = Date.now() - (hours * 60 * 60 * 1000);
          endTime = Date.now();
        }

        // SQL Query aufbauen
        let query = `
          SELECT exchange, symbol, funding_rate_percent, annualized_rate, collected_at
          FROM unified_funding_rates
          WHERE collected_at BETWEEN ? AND ?
        `;
        const params: any[] = [startTime, endTime];

        if (exchange) {
          query += ' AND exchange = ?';
          params.push(exchange);
        }

        if (symbol) {
          query += ' AND symbol = ?';
          params.push(symbol);
        }

        query += ' ORDER BY collected_at DESC LIMIT ?';
        params.push(limit);

        const { results } = await env.DB.prepare(query).bind(...params).all();

        // Response mit zusätzlichen Informationen
        const responseData: any = {
          symbol: symbol || 'all',
          exchange: exchange || 'all',
          count: results.length,
          results,
          timestamp: Date.now(),
        };

        if (queryMode === 'range') {
          responseData.startTime = startTime;
          responseData.endTime = endTime;
          responseData.startDate = new Date(startTime).toISOString();
          responseData.endDate = new Date(endTime).toISOString();
        } else {
          responseData.hours = hours;
        }

        return new Response(
          JSON.stringify(responseData),
          {
            headers: { ...corsHeaders, 'Content-Type': 'application/json' },
          }
        );
      }

      // ============================================
      // NEU: /debug Endpoint
      // ============================================
      if (path === '/debug') {
        const symbol = url.searchParams.get('symbol') || 'HYPE';
        
        // Alle HYPE Daten von Hyperliquid
        const hyperliquidData = await env.DB.prepare(`
          SELECT exchange, symbol, funding_rate_percent, collected_at,
                 datetime(collected_at/1000, 'unixepoch') as human_time
          FROM unified_funding_rates
          WHERE symbol = ? AND exchange = 'hyperliquid'
          ORDER BY collected_at DESC
          LIMIT 10
        `).bind(symbol).all();

        // Letzte Collection pro Exchange
        const lastCollections = await env.DB.prepare(`
          SELECT exchange, MAX(collected_at) as last_collection,
                 datetime(MAX(collected_at)/1000, 'unixepoch') as human_time,
                 COUNT(*) as total_records
          FROM unified_funding_rates
          WHERE symbol = ?
          GROUP BY exchange
        `).bind(symbol).all();

        // Anzahl Records in letzten 24h pro Exchange
        const last24h = Date.now() - (24 * 60 * 60 * 1000);
        const recent = await env.DB.prepare(`
          SELECT exchange, COUNT(*) as count_24h
          FROM unified_funding_rates
          WHERE symbol = ? AND collected_at > ?
          GROUP BY exchange
        `).bind(symbol, last24h).all();

        return new Response(
          JSON.stringify({
            symbol,
            hyperliquid_latest_10: hyperliquidData.results,
            last_collections_per_exchange: lastCollections.results,
            records_last_24h: recent.results,
            current_timestamp: Date.now(),
            current_time_human: new Date().toISOString(),
          }, null, 2),
          {
            headers: { ...corsHeaders, 'Content-Type': 'application/json' },
          }
        );
      }

      if (path === '/stats') {
        const totalQuery = await env.DB.prepare(`
          SELECT exchange, COUNT(*) as count
          FROM unified_funding_rates
          GROUP BY exchange
        `).all();

        const symbolsQuery = await env.DB.prepare(`
          SELECT exchange, COUNT(DISTINCT symbol) as symbols
          FROM unified_funding_rates
          GROUP BY exchange
        `).all();

        const latestQuery = await env.DB.prepare(
          `SELECT MAX(collected_at) as latest FROM unified_funding_rates`
        ).first();

        const oldestQuery = await env.DB.prepare(
          `SELECT MIN(collected_at) as oldest FROM unified_funding_rates`
        ).first();

        return new Response(
          JSON.stringify({
            totals: totalQuery.results,
            uniqueSymbols: symbolsQuery.results,
            timeRange: {
              oldest: oldestQuery?.oldest || null,
              latest: latestQuery?.latest || null,
            },
          }),
          {
            headers: { ...corsHeaders, 'Content-Type': 'application/json' },
          }
        );
      }

      if (path === '/collect/historical') {
        const exchange = url.searchParams.get('exchange');
        const symbol = url.searchParams.get('symbol');
        const startTime = parseInt(url.searchParams.get('startTime') || '0');
        const endTime = parseInt(url.searchParams.get('endTime') || Date.now().toString());

        if (!exchange || !symbol) {
          return new Response(JSON.stringify({ error: 'Missing exchange or symbol' }), {
            status: 400,
            headers: { ...corsHeaders, 'Content-Type': 'application/json' },
          });
        }

        let result;
        switch (exchange) {
          case 'aster':
            result = await collectHistoricalAster(env, symbol, startTime, endTime);
            break;
          case 'lighter':
            result = await collectHistoricalLighter(env, symbol, startTime, endTime);
            break;
          case 'hyperliquid':
            result = await collectHistoricalHyperliquid(env, symbol, startTime, endTime);
            break;
          case 'paradex':
            result = await collectHistoricalParadex(env, symbol, startTime, endTime);
            break;
          default:
            return new Response(JSON.stringify({ error: 'Invalid exchange' }), {
              status: 400,
              headers: { ...corsHeaders, 'Content-Type': 'application/json' },
            });
        }

        await saveToDBCurrent(env, exchange, result.unified, result.original);

        return new Response(
          JSON.stringify({
            success: true,
            exchange,
            symbol,
            records: result.unified.length,
          }),
          {
            headers: { ...corsHeaders, 'Content-Type': 'application/json' },
          }
        );
      }

      // ============================================
      // NEU: /paradex/hourly - Stündliche Aggregationen
      // ============================================
      if (path === '/paradex/hourly') {
        const symbol = url.searchParams.get('symbol');
        const hours = parseInt(url.searchParams.get('hours') || '24');
        const limit = parseInt(url.searchParams.get('limit') || '1000');

        const startTime = Date.now() - (hours * 60 * 60 * 1000);

        let query = `
          SELECT
            symbol,
            base_asset,
            hour_timestamp,
            avg_funding_rate,
            avg_funding_premium,
            avg_mark_price,
            avg_underlying_price,
            funding_index_start,
            funding_index_end,
            funding_index_delta,
            sample_count,
            datetime(hour_timestamp/1000, 'unixepoch') as hour_time
          FROM paradex_hourly_averages
          WHERE hour_timestamp >= ?
        `;

        const params: any[] = [startTime];

        if (symbol) {
          query += ' AND base_asset = ?';
          params.push(symbol);
        }

        query += ' ORDER BY hour_timestamp DESC LIMIT ?';
        params.push(limit);

        const { results } = await env.DB.prepare(query).bind(...params).all();

        return new Response(
          JSON.stringify({
            symbol: symbol || 'all',
            hours,
            count: results.length,
            results,
            timestamp: Date.now(),
          }),
          {
            headers: { ...corsHeaders, 'Content-Type': 'application/json' },
          }
        );
      }

      // ============================================
      // NEU: /paradex/minute - Minütliche Daten
      // ============================================
      if (path === '/paradex/minute') {
        const symbol = url.searchParams.get('symbol');
        const minutes = parseInt(url.searchParams.get('minutes') || '60');
        const limit = parseInt(url.searchParams.get('limit') || '1000');

        const startTime = Date.now() - (minutes * 60 * 1000);

        let query = `
          SELECT
            symbol,
            base_asset,
            funding_rate,
            funding_index,
            funding_premium,
            mark_price,
            underlying_price,
            collected_at,
            datetime(collected_at/1000, 'unixepoch') as collected_time
          FROM paradex_minute_data
          WHERE collected_at >= ?
        `;

        const params: any[] = [startTime];

        if (symbol) {
          query += ' AND base_asset = ?';
          params.push(symbol);
        }

        query += ' ORDER BY collected_at DESC LIMIT ?';
        params.push(limit);

        const { results } = await env.DB.prepare(query).bind(...params).all();

        return new Response(
          JSON.stringify({
            symbol: symbol || 'all',
            minutes,
            count: results.length,
            results,
            timestamp: Date.now(),
          }),
          {
            headers: { ...corsHeaders, 'Content-Type': 'application/json' },
          }
        );
      }

      // ============================================
      // NEU: /spot-markets - Spot-Märkte abrufen
      // ============================================
      if (path === '/spot-markets') {
        const exchange = url.searchParams.get('exchange');
        const symbol = url.searchParams.get('symbol');
        const limit = parseInt(url.searchParams.get('limit') || '1000');

        let query = `
          SELECT
            exchange,
            symbol,
            base_asset,
            quote_asset,
            status,
            collected_at,
            datetime(collected_at/1000, 'unixepoch') as collected_time
          FROM unified_spot_markets
          WHERE 1=1
        `;

        const params: any[] = [];

        if (exchange) {
          query += ' AND exchange = ?';
          params.push(exchange);
        }

        if (symbol) {
          query += ' AND symbol = ?';
          params.push(symbol);
        }

        query += ' ORDER BY collected_at DESC LIMIT ?';
        params.push(limit);

        const { results } = await env.DB.prepare(query).bind(...params).all();

        return new Response(
          JSON.stringify({
            exchange: exchange || 'all',
            symbol: symbol || 'all',
            count: results.length,
            results,
            timestamp: Date.now(),
          }),
          {
            headers: { ...corsHeaders, 'Content-Type': 'application/json' },
          }
        );
      }

      // ============================================
      // NEU: /spot-markets/collect - Manuelles Sammeln von Spot-Märkten
      // ============================================
      if (path === '/spot-markets/collect') {
        console.log('[API] Manual spot markets collection triggered');

        const spotResults = await Promise.allSettled([
          collectSpotMarketsHyperliquid(env),
          collectSpotMarketsLighter(env),
        ]);

        const stats = {
          hyperliquid: 0,
          lighter: 0,
          errors: [] as string[],
        };

        const exchanges = ['hyperliquid', 'lighter'];

        for (let i = 0; i < spotResults.length; i++) {
          const result = spotResults[i];
          const exchangeName = exchanges[i];

          if (result.status === 'fulfilled') {
            const { unified, original } = result.value;
            stats[exchangeName as keyof typeof stats] = unified.length;
            await saveSpotMarkets(env, exchangeName, unified, original);
          } else {
            const error = `${exchangeName}: ${result.reason}`;
            stats.errors.push(error);
            console.error(`[API] ${error}`);
          }
        }

        return new Response(JSON.stringify({ success: true, stats }), {
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        });
      }

      return new Response(JSON.stringify({ error: 'Not found' }), {
        status: 404,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    } catch (error: any) {
      console.error('[HTTP] Error:', error);
      return new Response(
        JSON.stringify({ error: error.message || 'Internal server error' }),
        {
          status: 500,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        }
      );
    }
  },
};