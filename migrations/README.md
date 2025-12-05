# Database Migrations

This directory contains SQL migration scripts for the funding-rate-collector database.

## Files

- `add_paradex_table.sql` - Adds Paradex exchange support (paradex_funding_history table)

## Usage

### Apply migration to local database (for development):
```bash
npx wrangler d1 execute funding-rates-db --local --file=migrations/add_paradex_table.sql
```

### Apply migration to remote database (production):
```bash
npx wrangler d1 execute funding-rates-db --remote --file=migrations/add_paradex_table.sql
```

### Verify migration was applied:
```bash
# Local
npx wrangler d1 execute funding-rates-db --local --command "SELECT name FROM sqlite_master WHERE type='table' AND name='paradex_funding_history';"

# Remote
npx wrangler d1 execute funding-rates-db --remote --command "SELECT name FROM sqlite_master WHERE type='table' AND name='paradex_funding_history';"
```

## Initial Setup

For a completely new database, use the main schema file:
```bash
npx wrangler d1 execute funding-rates-db --remote --file=schema.sql
```

## Migration History

1. **Initial Schema** - Base tables for Hyperliquid, Lighter, Aster, Binance
2. **add_paradex_table.sql** (2025-12-05) - Added Paradex exchange support
