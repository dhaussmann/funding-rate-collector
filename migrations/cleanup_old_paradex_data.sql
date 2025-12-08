-- Lösche alte Paradex Daten vor der Umstellung auf minütliche Collection

-- Entferne alte Paradex Einträge aus unified_funding_rates
DELETE FROM unified_funding_rates WHERE exchange = 'paradex';

-- Leere die alte paradex_funding_history Tabelle
DELETE FROM paradex_funding_history;

-- Leere neue Tabellen falls bereits Testdaten vorhanden
DELETE FROM paradex_minute_data;
DELETE FROM paradex_hourly_averages;

-- Zeige Anzahl verbleibender Einträge
SELECT
  'unified_funding_rates' as table_name,
  COUNT(*) as remaining_count
FROM unified_funding_rates
WHERE exchange = 'paradex'
UNION ALL
SELECT
  'paradex_funding_history',
  COUNT(*)
FROM paradex_funding_history
UNION ALL
SELECT
  'paradex_minute_data',
  COUNT(*)
FROM paradex_minute_data
UNION ALL
SELECT
  'paradex_hourly_averages',
  COUNT(*)
FROM paradex_hourly_averages;
