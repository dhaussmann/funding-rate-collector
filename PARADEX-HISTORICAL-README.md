# Paradex Historical Data Collection

## Overview

Five scripts for collecting Paradex historical funding rate data:

### 🚀 Recommended: Two-Phase Strategy

1. **`collect-paradex-recent.sh`** - Collect last 30 days FIRST (highest priority)
2. **`collect-paradex-backfill.sh`** - Iteratively collect older data (run multiple times)

### Alternative: Single-Run Collection

3. **`collect-paradex-historical-parallel.sh`** - Collect entire period at once
4. **`collect-paradex-historical.sh`** - Single-threaded (slower, for testing)
5. **`collect-paradex-historical-worker.sh`** - Worker script (used internally)

---

## 🎯 Quick Start (RECOMMENDED)

### Phase 1: Collect Recent Data (Last 30 Days)

```bash
./collect-paradex-recent.sh
```

**Why run this first?**
- ✅ Most recent data is most important
- ✅ Fast: ~2 hours for 30 days
- ✅ Get usable data immediately
- ✅ Safe to interrupt - newest data secured

**Runtime:** ~2 hours

---

### Phase 2: Backfill Historical Data

```bash
./collect-paradex-backfill.sh
```

**How it works:**
1. Finds oldest data in database
2. Collects 30 days before that
3. Stops when reaching 2025-01-01
4. **Run multiple times** until complete

**Example workflow:**
```bash
# First run: Collects Nov 8 - Dec 8
./collect-paradex-backfill.sh

# Second run: Collects Oct 9 - Nov 8
./collect-paradex-backfill.sh

# Continue until complete...
# Script will tell you when done!
```

**Runtime per iteration:** ~2 hours per 30-day period

**Total iterations needed:** ~11 iterations (341 days ÷ 30)

---

## Alternative: All-At-Once Collection

### Parallel Collection (Full Year)

```bash
./collect-paradex-historical-parallel.sh
```

**When to use:**
- You want all data in one run
- You can leave it running for ~10 hours
- You don't need incremental progress

**Runtime:** ~10 hours for full year

---

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

## Monitoring Progress

### Recent Collection
```bash
# Watch all workers
tail -f /tmp/tmp.*/worker_*.log

# Check specific worker
tail -f /tmp/tmp.*/worker_1.log
```

### Backfill Collection
```bash
# Check current status
wrangler d1 execute funding-rates-db --remote --command "
  SELECT
    datetime(MIN(collected_at)/1000, 'unixepoch') as oldest,
    datetime(MAX(collected_at)/1000, 'unixepoch') as newest,
    COUNT(*) as total_records
  FROM unified_funding_rates
  WHERE exchange = 'paradex'
"

# Watch workers
tail -f /tmp/tmp.*/worker_*.log
```

## Troubleshooting

**"Too Many Requests" error:**
- Increase `RATE_LIMIT` value (e.g., from 0.2 to 0.3)
- Reduce `NUM_WORKERS` (e.g., from 5 to 3)

**Worker hanging:**
- Check logs: `cat /tmp/tmp.*/worker_*.log`
- Verify API is accessible: `curl https://api.prod.paradex.trade/v1/markets/summary`

**Database errors:**
- Ensure wrangler is authenticated: `wrangler whoami`
- Check D1 database exists: `wrangler d1 list`

**Backfill script says "No data found":**
- Run `./collect-paradex-recent.sh` first
- This creates the initial data to backfill from

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
