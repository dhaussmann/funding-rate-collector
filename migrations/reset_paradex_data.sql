-- Reset Paradex data (removes Options contracts, keeps only PERP)
-- Run this after updating the Paradex collector to filter for PERP only

DELETE FROM paradex_funding_history;
DELETE FROM unified_funding_rates WHERE exchange = 'paradex';

-- Verify deletion
SELECT 'paradex_funding_history remaining records:', COUNT(*) FROM paradex_funding_history;
SELECT 'unified_funding_rates (paradex) remaining records:', COUNT(*) FROM unified_funding_rates WHERE exchange = 'paradex';
