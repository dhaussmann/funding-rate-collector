# Paradex Historical Data Collection

## Overview

Three scripts for collecting Paradex historical funding rate data:

1. **`collect-paradex-historical.sh`** - Single-threaded collection
2. **`collect-paradex-historical-parallel.sh`** - Multi-threaded master script (RECOMMENDED)
3. **`collect-paradex-historical-worker.sh`** - Worker script (called by parallel script)

## Quick Start

### Parallel Collection (Recommended - 5x faster)

```bash
./collect-paradex-historical-parallel.sh
```

**Features:**
- ✅ 5 parallel workers
- ✅ Optimal API rate limit usage (25 req/s = 1500 req/min)
- ✅ ~10 hours runtime for full year
- ✅ Individual worker logs for monitoring
- ✅ Automatic market distribution

**Monitor progress:**
```bash
# Watch all workers
tail -f /tmp/tmp.*/worker_*.log

# Watch specific worker
tail -f /tmp/tmp.*/worker_1.log
```

### Single-threaded Collection

```bash
./collect-paradex-historical.sh
```

**When to use:**
- Testing with small datasets
- Lower system resource usage
- Simpler debugging

**Runtime:** ~50 hours for full year (5x slower)

## Configuration

Edit at the top of each script:

```bash
START_TIME=1735689600000  # 2025-01-01 00:00:00 UTC
END_TIME=$(date +%s)000   # Now (or set specific date)
SAMPLE_INTERVAL=3600000   # 1 hour (adjust for more/less granularity)
```

### Sampling Strategy

- **SAMPLE_INTERVAL**: How often to take a snapshot (default: 1 hour)
- **CHUNK_SIZE**: Duration of each snapshot (default: 5 minutes = 60 data points)

Example: With 1-hour interval, collects 5 minutes of data every hour.

## API Rate Limits

Paradex API limits: **1500 requests/minute** (25 req/s) per IP

### Parallel Script
- 5 workers × 5 req/s = **25 req/s total**
- Exactly at API limit ✅

### Single Script
- 1 worker × 5 req/s = **5 req/s total**
- Only 20% of capacity (slower but safer)

## Data Storage

Both scripts store data in:
- **`unified_funding_rates`** - Standardized format across all exchanges
- **`paradex_hourly_averages`** - Paradex-specific detailed data

## Performance

For 341 days (2025-01-01 to 2025-12-08), 111 markets:

| Script | Workers | Runtime | API Usage |
|--------|---------|---------|-----------|
| Parallel | 5 | ~10 hours | 100% (1500 req/min) |
| Single | 1 | ~50 hours | 20% (300 req/min) |

## Troubleshooting

**"Too Many Requests" error:**
- Increase `RATE_LIMIT` value (e.g., from 0.2 to 0.3)
- Reduce `NUM_WORKERS` in parallel script

**Worker hanging:**
- Check logs: `cat /tmp/tmp.*/worker_*.log`
- Verify API is accessible: `curl https://api.prod.paradex.trade/v1/markets/summary`

**Database errors:**
- Ensure wrangler is authenticated: `wrangler whoami`
- Check D1 database exists: `wrangler d1 list`

## Example Output

```
[W1][  5%] (  5/22) BTC-USD-PERP    ✓ 168 hourly
[W2][  8%] (  2/23) ETH-USD-PERP    ✓ 168 hourly
[W3][  4%] (  1/22) SOL-USD-PERP    ✓ 168 hourly
```

## Notes

- Scripts use `INSERT OR IGNORE` - safe to re-run without duplicates
- Logs are kept in temp directory until you choose to delete
- Press Ctrl+C to stop - workers will finish current market before exiting
