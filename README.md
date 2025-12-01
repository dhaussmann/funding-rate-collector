# Funding Rate Collector

A Cloudflare Worker that collects and compares funding rates from multiple cryptocurrency exchanges (Hyperliquid, Lighter, Aster).

## Features

- ✅ **Automatic hourly collection** via Cron Jobs
- ✅ **Multi-exchange support**: Hyperliquid, Lighter, Aster, Binance
- ✅ **Standardized data format** across all exchanges
- ✅ **REST API** for querying and comparing rates
- ✅ **Historical data collection** scripts
- ✅ **D1 Database** for persistent storage

## API Endpoints

### Compare Rates
```bash
GET /compare?symbol=HYPE
```
Compare funding rates across all exchanges for a specific symbol.

### Historical Data
```bash
GET /history?symbol=HYPE&hours=24
```
Get historical funding rates for the last X hours.

### Latest Rates
```bash
GET /latest?exchange=hyperliquid&symbol=BTC
```
Get the latest funding rates with optional filters.

### Statistics
```bash
GET /stats
```
Get collection statistics.

### Manual Collection
```bash
POST /collect
```
Manually trigger data collection.

## Setup

### 1. Install Dependencies
```bash
npm install
```

### 2. Configure Database
```bash
# Create D1 database
wrangler d1 create funding-rates-db

# Copy the database_id and update wrangler.toml
# database_id = "your-database-id-here"

# Initialize schema
wrangler d1 execute funding-rates-db --file=./schema.sql
```

### 3. Deploy
```bash
wrangler deploy
```

## Project Structure

```
funding-rate-collector/
├── src/
│   ├── index.ts              # Main worker entry point
│   ├── types.ts              # TypeScript types
│   ├── collectors/           # Exchange collectors
│   │   ├── index.ts
│   │   ├── hyperliquid.ts
│   │   ├── lighter.ts
│   │   ├── aster.ts
│   │   └── binance.ts
│   └── database/
│       └── operations.ts     # Database operations
├── scripts/                  # Data collection scripts
│   ├── collect-hyperliquid-paginated.sh
│   └── reset-hyperliquid-tables.sh
├── schema.sql                # Database schema
├── wrangler.toml             # Cloudflare configuration
└── package.json
```

## Data Format

All funding rates are stored in a standardized format:

```typescript
{
  exchange: string;           // "hyperliquid", "lighter", "aster"
  symbol: string;             // "BTC", "ETH", "HYPE"
  funding_rate: number;       // Decimal: 0.000125
  funding_rate_percent: number; // Percent: 0.0125
  annualized_rate: number;    // Annualized: 13.6875
  collected_at: number;       // Unix timestamp (ms)
}
```

## Historical Data Collection

For Hyperliquid historical data:

```bash
# Reset tables (optional)
./scripts/reset-hyperliquid-tables.sh

# Collect historical data (with pagination)
./scripts/collect-hyperliquid-paginated.sh
```

## Development

```bash
# Local development
npm run dev

# Test endpoints
curl http://localhost:8787/health
curl http://localhost:8787/compare?symbol=HYPE
```

## Deployment

The worker runs automatically every hour via Cron Jobs:
```toml
[triggers]
crons = ["0 * * * *"]
```

## Environment Variables

No API keys required! All exchange APIs are public.

## Database Schema

See `schema.sql` for the complete database structure including:
- `unified_funding_rates` - Main table for all exchanges
- `hyperliquid_funding_history` - Hyperliquid original data
- `lighter_funding_history` - Lighter original data
- `aster_funding_history` - Aster original data

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

MIT

## Support

For issues or questions, please open an issue on GitHub.