import { Env } from './types';
import {
  collectCurrentHyperliquid,
  collectCurrentLighter,
  collectCurrentAster,
  collectHistoricalAster,
  collectHistoricalLighter,
  collectHistoricalHyperliquid,
} from './collectors';
import { saveToDBCurrent } from './database/operations';

export default {
  async scheduled(event: ScheduledEvent, env: Env, ctx: ExecutionContext): Promise<void> {
    console.log('[CRON] Starting hourly funding rate collection...');
    const startTime = Date.now();

    try {
      const results = await Promise.allSettled([
        collectCurrentHyperliquid(env),
        collectCurrentLighter(env),
        collectCurrentAster(env),
      ]);

      const stats = {
        hyperliquid: 0,
        lighter: 0,
        aster: 0,
        errors: [] as string[],
      };

      for (let i = 0; i < results.length; i++) {
        const result = results[i];
        const exchangeName = ['hyperliquid', 'lighter', 'aster'][i];

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

      const duration = Date.now() - startTime;
      console.log('[CRON] Collection completed:', { ...stats, duration: `${duration}ms` });
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
          'Funding Rate Collector API\n\nEndpoints:\n- /health\n- /collect\n- /rates\n- /compare?symbol=BTC\n- /history?symbol=HYPE&hours=24\n- /debug?symbol=HYPE\n- /stats',
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
        ]);

        const stats = {
          hyperliquid: 0,
          lighter: 0,
          aster: 0,

          errors: [] as string[],
        };

        const exchanges = ['hyperliquid', 'lighter', 'aster'];

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
        const limit = parseInt(url.searchParams.get('limit') || '100');

        let query = 'SELECT * FROM unified_funding_rates WHERE 1=1';
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
        const limit = parseInt(url.searchParams.get('limit') || '1000');

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