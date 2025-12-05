-- ============================================
-- ORIGINALE DATEN (pro Börse getrennt)
-- ============================================

-- Hyperliquid Original-Daten
CREATE TABLE hyperliquid_funding_history (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  coin TEXT NOT NULL,
  funding_rate REAL NOT NULL,
  collected_at INTEGER NOT NULL,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX idx_hl_coin_time ON hyperliquid_funding_history(coin, collected_at);

-- Lighter Original-Daten
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
CREATE INDEX idx_lt_symbol_time ON lighter_funding_history(symbol, collected_at);
CREATE INDEX idx_lt_market_time ON lighter_funding_history(market_id, timestamp);

-- Aster Original-Daten
CREATE TABLE aster_funding_history (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  symbol TEXT NOT NULL,
  base_asset TEXT NOT NULL,
  funding_rate REAL NOT NULL,
  funding_time INTEGER NOT NULL,
  collected_at INTEGER NOT NULL,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX idx_aster_symbol_time ON aster_funding_history(symbol, collected_at);

-- Binance Original-Daten
CREATE TABLE binance_funding_history (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  symbol TEXT NOT NULL,
  base_asset TEXT NOT NULL,
  funding_rate REAL NOT NULL,
  funding_time INTEGER NOT NULL,
  collected_at INTEGER NOT NULL,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX idx_binance_symbol_time ON binance_funding_history(symbol, collected_at);

-- Paradex Original-Daten
CREATE TABLE paradex_funding_history (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  symbol TEXT NOT NULL,
  base_asset TEXT NOT NULL,
  funding_rate REAL NOT NULL,
  mark_price REAL,
  last_traded_price REAL,
  collected_at INTEGER NOT NULL,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX idx_paradex_symbol_time ON paradex_funding_history(symbol, collected_at);

-- ============================================
-- VEREINHEITLICHTE DATEN (alle Börsen zusammen)
-- ============================================

CREATE TABLE unified_funding_rates (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  exchange TEXT NOT NULL,
  symbol TEXT NOT NULL,
  trading_pair TEXT NOT NULL,
  funding_rate REAL NOT NULL,
  funding_rate_percent REAL NOT NULL,
  annualized_rate REAL,
  collected_at INTEGER NOT NULL,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_unified_exchange_symbol ON unified_funding_rates(exchange, symbol);
CREATE INDEX idx_unified_symbol_time ON unified_funding_rates(symbol, collected_at);
CREATE INDEX idx_unified_collected ON unified_funding_rates(collected_at);

-- ============================================
-- METADATEN für historische Sammlung
-- ============================================

CREATE TABLE collection_progress (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  exchange TEXT NOT NULL,
  symbol TEXT NOT NULL,
  start_time INTEGER NOT NULL,
  end_time INTEGER NOT NULL,
  status TEXT NOT NULL, -- 'pending', 'in_progress', 'completed', 'failed'
  records_collected INTEGER DEFAULT 0,
  error_message TEXT,
  updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  UNIQUE(exchange, symbol, start_time)
);