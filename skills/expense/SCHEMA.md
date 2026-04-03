# Expense DB Schema

Database: `expense` (PostgreSQL, localhost)

## Tables

### categories

| Column | Type | Description |
|--------|------|-------------|
| id | SERIAL PK | Auto-increment ID |
| name | TEXT UNIQUE | 分類名稱（如「餐飲」「交通」） |
| icon | TEXT | Emoji icon |
| applicable_type | category_scope ENUM | `expense`, `income`, or `both` |
| created_at | TIMESTAMPTZ | 建立時間 |

### transactions

| Column | Type | Description |
|--------|------|-------------|
| id | SERIAL PK | Auto-increment ID |
| type | tx_type ENUM | `expense` or `income` |
| amount | INTEGER CHECK >0 | 金額（TWD，正整數，靠 type 區分方向） |
| category_id | INTEGER FK→categories | 分類 |
| description | TEXT | 品項描述 |
| note | TEXT NULL | 額外備註 |
| discord_user_id | TEXT | Discord snowflake ID（隔離用戶） |
| discord_user_name | TEXT | Discord 顯示名稱（報表用） |
| tx_date | DATE | 消費/收入日期（可回溯） |
| created_at | TIMESTAMPTZ | 記錄建立時間 |

### recurring_expenses

| Column | Type | Description |
|--------|------|-------------|
| id | SERIAL PK | Auto-increment ID |
| name | TEXT | 固定開銷名稱（如「房租」「Spotify」） |
| amount | INTEGER CHECK >0 | 每期金額（TWD，正整數） |
| category_id | INTEGER FK→categories | 分類 |
| frequency | TEXT DEFAULT 'monthly' | 頻率（目前僅 monthly） |
| note | TEXT NULL | 額外備註 |
| discord_user_id | TEXT | Discord snowflake ID（隔離用戶） |
| discord_user_name | TEXT | Discord 顯示名稱 |
| is_active | BOOLEAN DEFAULT true | 是否啟用（停用 = soft delete） |
| created_at | TIMESTAMPTZ | 記錄建立時間 |

## Enums

- `tx_type`: `'expense'`, `'income'`
- `category_scope`: `'expense'`, `'income'`, `'both'`

## Indexes

- `idx_tx_date` on transactions(tx_date)
- `idx_tx_category` on transactions(category_id)
- `idx_tx_user` on transactions(discord_user_id)
- `idx_tx_type` on transactions(type)
- `idx_recurring_user` on recurring_expenses(discord_user_id)
- `idx_recurring_active` on recurring_expenses(is_active)

## Default Categories

| Name | Icon | Scope |
|------|------|-------|
| 餐飲 | 🍽️ | expense |
| 交通 | 🚗 | expense |
| 日用品 | 🧴 | expense |
| 娛樂 | 🎮 | expense |
| 醫療 | 🏥 | expense |
| 教育 | 📚 | both |
| 居住 | 🏠 | expense |
| 服飾 | 👕 | expense |
| 薪資 | 💰 | income |
| 投資 | 📈 | both |
| 其他 | 📦 | both |
