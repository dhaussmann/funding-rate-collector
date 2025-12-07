-- Paradex Minütliche Daten (gesammelt über WebSocket)
CREATE TABLE IF NOT EXISTS paradex_minute_data (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  symbol TEXT NOT NULL,
  base_asset TEXT NOT NULL,
  funding_rate REAL NOT NULL,
  funding_index REAL NOT NULL,
  funding_premium REAL NOT NULL,
  mark_price REAL NOT NULL,
  underlying_price REAL,
  collected_at INTEGER NOT NULL,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_paradex_minute_symbol_time
  ON paradex_minute_data(symbol, collected_at);

CREATE INDEX IF NOT EXISTS idx_paradex_minute_base_time
  ON paradex_minute_data(base_asset, collected_at);

-- Paradex Stündliche Aggregationen
CREATE TABLE IF NOT EXISTS paradex_hourly_averages (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  symbol TEXT NOT NULL,
  base_asset TEXT NOT NULL,
  hour_timestamp INTEGER NOT NULL,

  -- Durchschnittswerte (aus 60 Minuten)
  avg_funding_rate REAL NOT NULL,
  avg_funding_premium REAL NOT NULL,
  avg_mark_price REAL NOT NULL,
  avg_underlying_price REAL,

  -- Funding Index Delta (tatsächliche 1h Zahlung)
  funding_index_start REAL NOT NULL,
  funding_index_end REAL NOT NULL,
  funding_index_delta REAL NOT NULL,

  -- Metadaten
  sample_count INTEGER NOT NULL,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,

  UNIQUE(symbol, hour_timestamp)
);

CREATE INDEX IF NOT EXISTS idx_paradex_hourly_symbol_time
  ON paradex_hourly_averages(symbol, hour_timestamp);

CREATE INDEX IF NOT EXISTS idx_paradex_hourly_base_time
  ON paradex_hourly_averages(base_asset, hour_timestamp);
