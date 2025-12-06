-- Reset Lighter Tables
-- This script deletes all Lighter data from both tables

-- Option 1: Delete all Lighter data (keeps table structure)
DELETE FROM lighter_funding_history;
DELETE FROM unified_funding_rates WHERE exchange = 'lighter';

-- Verify deletion
SELECT 'lighter_funding_history remaining records:', COUNT(*) FROM lighter_funding_history;
SELECT 'unified_funding_rates (lighter) remaining records:', COUNT(*) FROM unified_funding_rates WHERE exchange = 'lighter';
