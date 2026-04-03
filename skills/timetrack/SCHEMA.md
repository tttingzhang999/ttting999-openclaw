# Timetrack DB Schema

Database: `timetrack` (PostgreSQL, localhost)

> 公司對外以「人天」(person-day) 計費，但內部以小時追蹤（精度 0.1h）。
> 轉換公式：`client_days = internal_hours / hours_per_day`（預設 8）。

## Tables

### projects

| Column | Type | Default | Description |
|--------|------|---------|-------------|
| id | TEXT PK | — | 專案代碼（如 `gaia2`） |
| name | TEXT NOT NULL | — | 專案名稱 |
| client | TEXT | NULL | 客戶名稱 |
| billing_unit | TEXT | `'person-day'` | 計費單位 |
| hours_per_day | NUMERIC | `8` | 一人天 = 幾小時（用於 L1→L3 轉換） |
| created_at | TIMESTAMPTZ | `now()` | 建立時間 |

### entries

| Column | Type | Default | Description |
|--------|------|---------|-------------|
| id | SERIAL PK | auto | Auto-increment ID |
| date | DATE NOT NULL | `CURRENT_DATE` | 工作日期 |
| project_id | TEXT FK→projects | — | 專案代碼 |
| epic | TEXT | NULL | 工項大類 |
| task | TEXT NOT NULL | — | 任務描述 |
| subtask | TEXT | NULL | 子任務 |
| actual_hours | NUMERIC NOT NULL | — | **L1**: 實際投入時間（小時，精度 0.1h） |
| internal_hours | NUMERIC | NULL | **L2**: 公司內部認列時數 |
| client_days | NUMERIC | NULL | **L3**: 對客戶計費人天 |
| notes | TEXT | NULL | 備註 |
| created_at | TIMESTAMPTZ | `now()` | 記錄建立時間 |

## 3-Layer Model

| Layer | Column | Unit | Description |
|-------|--------|------|-------------|
| L1 | actual_hours | 小時 (0.1h) | 實際花的時間 |
| L2 | internal_hours | 小時 | 公司內部認列（通常 ≥ L1） |
| L3 | client_days | 人天 | 對客戶報價/計費 |

**轉換**：`client_days = internal_hours / hours_per_day`

**比率指標**：
- Credit Ratio = L2 / L1（內部認列倍率）
- Revenue Ratio = L3 / L1（每小時產出人天）
- Pricing Leverage = L3 / L2（公司加價倍率）

## Indexes

- `idx_entries_project_epic_date` on `entries(project_id, epic, date)`
