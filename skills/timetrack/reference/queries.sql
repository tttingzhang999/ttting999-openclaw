-- =============================================================
-- Timetrack report queries
-- Usage: psql -d timetrack -v project='gaia2' -f queries.sql
-- =============================================================

-- 1. Per-epic ratio report
-- Credit Ratio   = internal_hours / actual_hours
-- Revenue Ratio   = client_days   / actual_hours
-- Pricing Leverage = client_days   / internal_hours
SELECT
  epic,
  SUM(actual_hours)   AS actual_h,
  SUM(internal_hours) AS internal_h,
  SUM(client_days)    AS client_d,
  ROUND(SUM(internal_hours) / NULLIF(SUM(actual_hours), 0), 2)   AS credit_ratio,
  ROUND(SUM(client_days)    / NULLIF(SUM(actual_hours), 0), 2)   AS revenue_ratio,
  ROUND(SUM(client_days)    / NULLIF(SUM(internal_hours), 0), 2) AS pricing_leverage
FROM entries
WHERE project_id = :'project'
GROUP BY epic
ORDER BY epic;

-- 2. Weekly recap (last 7 days)
SELECT date, epic, task, subtask, actual_hours, internal_hours, client_days
FROM entries
WHERE project_id = :'project'
  AND date >= CURRENT_DATE - INTERVAL '7 days'
ORDER BY date DESC, created_at DESC;

-- 3. Entries missing L2/L3 data
SELECT id, date, epic, task, actual_hours
FROM entries
WHERE project_id = :'project'
  AND (internal_hours IS NULL OR client_days IS NULL)
ORDER BY date DESC;

-- 4. Per-project summary
SELECT
  p.id,
  p.name,
  COUNT(e.id) AS entries,
  COALESCE(SUM(e.actual_hours), 0) AS total_actual_h,
  COALESCE(SUM(e.internal_hours), 0) AS total_internal_h,
  COALESCE(SUM(e.client_days), 0) AS total_client_d
FROM projects p
LEFT JOIN entries e ON e.project_id = p.id
GROUP BY p.id, p.name
ORDER BY p.id;
