---
name: timetrack
description: >-
  Tracks personal work hours across 3 layers (actual time, internal credit,
  client billing) per project and epic. Logs time entries, recaps current
  work items, batch-updates internal/client reference numbers, and generates
  ratio reports with work item classification. Use when the user mentions
  logging work time, tracking hours, recapping work items, or analyzing
  time-to-revenue efficiency. Also triggers on: /timetrack, 記工時, 工時紀錄.
---

# Timetrack — Personal Work Hour Tracker

## DB Connection

All data operations use psql against `timetrack` database on localhost:

```bash
psql -d timetrack -c "SQL_HERE"
```

For queries with variables, use `-v`:

```bash
psql -d timetrack -v project="'gaia2'" -c "SELECT ... WHERE project_id = :'project'"
```

## Commands

Parse `$ARGUMENTS` to determine which command to run. Default to **log** if arguments contain a time value (e.g. `1h`, `0.5h`, `30m`, `2小時`).

---

### 1. log — Record a time entry

**Parse from natural language:**
- Time: `1h`, `0.5h`, `30m`, `2小時`, `半小時` → convert to decimal hours
- Project: use active project from conversation context, or ask
- Epic/task/subtask: extract from description

**Insert:**

```bash
psql -d timetrack -c "
INSERT INTO entries (date, project_id, epic, task, subtask, actual_hours, notes)
VALUES (CURRENT_DATE, '<project>', '<epic>', '<task>', '<subtask>', <hours>, '<notes>')
RETURNING id, date, task, actual_hours;
"
```

**Confirm to user in table format:**

```
✓ 已記錄
| 日期 | 專案 | Epic | Task | 實際時間 |
|------|------|------|------|---------|
| 4/2  | gaia2 | observability | OTEL SDK 導入 | 1h |
```

---

### 2. recap — Show recent work & status

**Default: last 7 days for active project.**

```bash
psql -d timetrack -c "
SELECT date, epic, task, subtask, actual_hours, internal_hours, client_days
FROM entries
WHERE project_id = '<project>'
  AND date >= CURRENT_DATE - INTERVAL '7 days'
ORDER BY date DESC, created_at DESC;
"
```

Also show:
- Total actual hours this week
- Count of entries missing L2/L3 data
- Per-epic subtotals

---

### 3. ref — Batch update internal/client numbers

User provides L2 (internal hours) and/or L3 (client days) for a scope.

**Parse:** `/timetrack ref <epic> 內部 <N>h 客戶 <N>d` or similar natural language.

**Distribute proportionally** across entries by actual_hours ratio:

```bash
psql -d timetrack -c "
WITH scope AS (
  SELECT id, actual_hours,
    actual_hours / SUM(actual_hours) OVER () AS ratio
  FROM entries
  WHERE project_id = '<project>'
    AND epic = '<epic>'
    AND date >= '<start_date>'
    AND date <= '<end_date>'
    AND internal_hours IS NULL
)
UPDATE entries e
SET internal_hours = ROUND(scope.ratio * <total_internal>, 2)
FROM scope
WHERE e.id = scope.id;
"
```

Same pattern for `client_days`. Confirm updated count.

---

### 4. report — Ratio analysis & classification

Read [reference/queries.sql](reference/queries.sql) for the full query. Run the per-epic ratio query:

```bash
psql -d timetrack -c "
SELECT epic,
  SUM(actual_hours) AS actual_h,
  SUM(internal_hours) AS internal_h,
  SUM(client_days) AS client_d,
  ROUND(SUM(internal_hours) / NULLIF(SUM(actual_hours), 0), 2) AS credit_ratio,
  ROUND(SUM(client_days) / NULLIF(SUM(actual_hours), 0), 2) AS revenue_ratio,
  ROUND(SUM(client_days) / NULLIF(SUM(internal_hours), 0), 2) AS pricing_leverage
FROM entries
WHERE project_id = '<project>'
GROUP BY epic ORDER BY epic;
"
```

**Classify each epic** using thresholds from [reference/classification.md](reference/classification.md):

| Type | Credit Ratio | Revenue Ratio | Label |
|------|-------------|---------------|-------|
| 黃金工項 | > 2.0 | > 0.3 d/h | 多接、主導 |
| 政治型 | > 2.0 | < 0.15 d/h | 升遷有用 |
| 苦工型 | < 1.2 | < 0.15 d/h | 少接 |
| 商業槓桿 | 1.2–2.0 | > 0.3 d/h | 往 solution 走 |

Output as a combined table with ratios + classification. Flag epics with insufficient L2/L3 data.

---

### 5. project — Manage projects

**Add:**
```bash
psql -d timetrack -c "
INSERT INTO projects (id, name, client) VALUES ('<id>', '<name>', '<client>')
ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name, client = EXCLUDED.client;
"
```

**List:**
```bash
psql -d timetrack -c "
SELECT p.id, p.name, p.client, COUNT(e.id) AS entries
FROM projects p LEFT JOIN entries e ON e.project_id = p.id
GROUP BY p.id, p.name, p.client ORDER BY p.id;
"
```

---

### 6. set-project — Set active project for session

Remember the project ID for subsequent commands in this conversation. If no project is set and only one project exists, use it automatically.

---

## Output Language

Respond in 繁體中文. Use table format for data display.

## Schema Reference

For DB setup or schema questions, see [reference/schema.sql](reference/schema.sql).
