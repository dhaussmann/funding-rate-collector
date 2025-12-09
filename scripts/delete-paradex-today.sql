-- Skript zum Löschen der fehlerhaften Paradex-Daten von heute
-- Datum: 2025-12-09 (Timestamp: 1765296000000 entspricht ca. 2025-12-09 12:00:00 UTC)

-- Berechne den Start des heutigen Tages (00:00:00 UTC)
-- 2025-12-09 00:00:00 UTC = 1765324800000 ms
-- Berechne das Ende des heutigen Tages (23:59:59 UTC)
-- 2025-12-09 23:59:59 UTC = 1765411199000 ms

-- Überprüfe zuerst, welche Daten betroffen sind
SELECT 'unified_funding_rates' as table_name, COUNT(*) as count_to_delete
FROM unified_funding_rates
WHERE exchange = 'paradex'
  AND collected_at >= 1733702400000  -- 2025-12-09 00:00:00 UTC
  AND collected_at < 1733788800000;  -- 2025-12-10 00:00:00 UTC

SELECT 'paradex_minute_data' as table_name, COUNT(*) as count_to_delete
FROM paradex_minute_data
WHERE collected_at >= 1733702400000
  AND collected_at < 1733788800000;

SELECT 'paradex_hourly_averages' as table_name, COUNT(*) as count_to_delete
FROM paradex_hourly_averages
WHERE hour_timestamp >= 1733702400000
  AND hour_timestamp < 1733788800000;

-- Lösche die fehlerhaften Daten
-- HINWEIS: Kommentiere die folgenden DELETE-Befehle ein, nachdem du die Counts überprüft hast!

-- DELETE FROM unified_funding_rates
-- WHERE exchange = 'paradex'
--   AND collected_at >= 1733702400000
--   AND collected_at < 1733788800000;

-- DELETE FROM paradex_minute_data
-- WHERE collected_at >= 1733702400000
--   AND collected_at < 1733788800000;

-- DELETE FROM paradex_hourly_averages
-- WHERE hour_timestamp >= 1733702400000
--   AND hour_timestamp < 1733788800000;
