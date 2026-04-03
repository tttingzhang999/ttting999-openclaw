# Worklog DB Schema

Database: `worklog` (PostgreSQL, localhost)

## Tables

### items

| Column | Type | Default | Description |
|--------|------|---------|-------------|
| id | SERIAL PK | auto | Auto-increment ID |
| type | TEXT NOT NULL | — | `task`, `note`, or `todo` |
| content | TEXT NOT NULL | — | 事項描述 |
| project | TEXT | NULL | 關聯的 timetrack project ID |
| status | TEXT NOT NULL | `'open'` | `open`, `in_progress`, `done`, `cancelled` |
| priority | TEXT NOT NULL | `'normal'` | `low`, `normal`, `high`, `urgent` |
| due_date | DATE | NULL | 截止日期 |
| tags | TEXT[] | NULL | 標籤陣列 |
| created_at | TIMESTAMPTZ | `NOW()` | 建立時間 |
| updated_at | TIMESTAMPTZ | `NOW()` | 最後更新時間 |
| completed_at | TIMESTAMPTZ | NULL | 完成時間（status = done 時設定） |

## Type 說明

| Type | 用途 | 範例 |
|------|------|------|
| `note` | 正在做的事、觀察、紀錄 | 「在寫 API 文件」 |
| `todo` | 需要做但尚未開始 | 「要完成 code review」 |
| `task` | 有 deadline 的具體工作項目 | 「週五前完成部署」 |

## Indexes

- `idx_items_status` on `items(status)`
- `idx_items_project` on `items(project)`
- `idx_items_created` on `items(created_at)`
- `idx_items_type` on `items(type)`
