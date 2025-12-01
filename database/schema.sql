-- Hyperliquid Original
CREATE TABLE hyperliquid_funding_history (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  coin TEXT NOT NULL,
  funding_rate REAL NOT NULL,
  collected_at INTEGER NOT NULL,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX idx_hl_coin_time ON hyperliquid_funding_history(coin, collected_at);

-- Lighter Original
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

-- Aster Original
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

-- Binance Original
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

-- Unified Table
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
