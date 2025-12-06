-- Complete Reset: Drop and Recreate Lighter Tables
-- This script completely removes and recreates the Lighter table structure

-- Drop existing table and index
DROP TABLE IF EXISTS lighter_funding_history;

-- Recreate Lighter table (from schema.sql)
CREATE TABLE lighter_funding_history (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  market_id INTEGER NOT NULL,
  symbol TEXT NOT NULL,
  timestamp INTEGER NOT NULL,
  rate REAL NOT NULL,
  direction TEXT NOT NULL,
  collected_at INTEGER NOT NULL,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- Recreate indexes
CREATE INDEX idx_lt_symbol_time ON lighter_funding_history(symbol, collected_at);
CREATE INDEX idx_lt_market_time ON lighter_funding_history(market_id, timestamp);

-- Delete from unified table
DELETE FROM unified_funding_rates WHERE exchange = 'lighter';

-- Verify
SELECT 'lighter_funding_history records:', COUNT(*) FROM lighter_funding_history;
SELECT 'unified_funding_rates (lighter) records:', COUNT(*) FROM unified_funding_rates WHERE exchange = 'lighter';
