-- Migration: Simplified spot markets tables
-- Created: 2025-12-13
-- Purpose: Store only exchange and symbol for available spot markets

-- Drop old tables if they exist
DROP TABLE IF EXISTS hyperliquid_spot_markets;
DROP TABLE IF EXISTS lighter_spot_markets;
DROP TABLE IF EXISTS unified_spot_markets;

-- ============================================
-- UNIFIED SPOT MARKETS (simplified)
-- ============================================

CREATE TABLE unified_spot_markets (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  exchange TEXT NOT NULL,
  symbol TEXT NOT NULL,
  collected_at INTEGER NOT NULL,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  UNIQUE(exchange, symbol)
);

CREATE INDEX idx_unified_spot_exchange ON unified_spot_markets(exchange);
CREATE INDEX idx_unified_spot_symbol ON unified_spot_markets(symbol);
CREATE INDEX idx_unified_spot_collected ON unified_spot_markets(collected_at);
