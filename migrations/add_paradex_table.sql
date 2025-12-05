-- Paradex Original-Daten
CREATE TABLE IF NOT EXISTS paradex_funding_history (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  symbol TEXT NOT NULL,
  base_asset TEXT NOT NULL,
  funding_rate REAL NOT NULL,
  mark_price REAL,
  last_traded_price REAL,
  collected_at INTEGER NOT NULL,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_paradex_symbol_time ON paradex_funding_history(symbol, collected_at);
