-- Migration: Add spot markets tables for Hyperliquid and Lighter
-- Created: 2025-12-13
-- Purpose: Store available spot markets from exchanges for daily tracking

-- ============================================
-- HYPERLIQUID SPOT MARKETS
-- ============================================

CREATE TABLE IF NOT EXISTS hyperliquid_spot_markets (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  token_name TEXT NOT NULL,
  token_id TEXT,
  sz_decimals INTEGER,
  wei_decimals INTEGER,
  is_canonical INTEGER DEFAULT 1,
  collected_at INTEGER NOT NULL,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_hl_spot_token_time ON hyperliquid_spot_markets(token_name, collected_at);
CREATE INDEX IF NOT EXISTS idx_hl_spot_collected ON hyperliquid_spot_markets(collected_at);

-- ============================================
-- LIGHTER SPOT MARKETS
-- ============================================

CREATE TABLE IF NOT EXISTS lighter_spot_markets (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  market_id INTEGER NOT NULL,
  symbol TEXT NOT NULL,
  base_asset TEXT,
  quote_asset TEXT,
  status TEXT NOT NULL,
  market_type TEXT,
  collected_at INTEGER NOT NULL,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_lt_spot_symbol_time ON lighter_spot_markets(symbol, collected_at);
CREATE INDEX IF NOT EXISTS idx_lt_spot_market_time ON lighter_spot_markets(market_id, collected_at);
CREATE INDEX IF NOT EXISTS idx_lt_spot_collected ON lighter_spot_markets(collected_at);

-- ============================================
-- UNIFIED SPOT MARKETS (all exchanges combined)
-- ============================================

CREATE TABLE IF NOT EXISTS unified_spot_markets (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  exchange TEXT NOT NULL,
  symbol TEXT NOT NULL,
  base_asset TEXT,
  quote_asset TEXT,
  status TEXT DEFAULT 'active',
  collected_at INTEGER NOT NULL,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_unified_spot_exchange_symbol ON unified_spot_markets(exchange, symbol);
CREATE INDEX IF NOT EXISTS idx_unified_spot_symbol ON unified_spot_markets(symbol);
CREATE INDEX IF NOT EXISTS idx_unified_spot_collected ON unified_spot_markets(collected_at);
