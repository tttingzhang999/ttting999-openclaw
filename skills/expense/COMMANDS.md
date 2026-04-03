# expense.sh 指令參考

## 目錄

- [add](#add) — 新增交易
- [categories](#categories) — 查詢分類
- [add-category](#add-category) — 新增分類
- [summary](#summary) — 月報
- [list](#list) — 近期紀錄
- [delete](#delete) — 刪除紀錄
- [update](#update) — 修改紀錄
- [recurring-add](#recurring-add) — 新增固定開銷
- [recurring-list](#recurring-list) — 列出固定開銷
- [recurring-update](#recurring-update) — 修改固定開銷
- [recurring-delete](#recurring-delete) — 刪除固定開銷

---

## add

新增一筆交易紀錄。

```bash
bash {baseDir}/scripts/expense.sh add \
  --type <expense|income> \
  --amount <正整數> \
  --category "分類名稱" \
  --desc "品項描述" \
  --user-id "discord_user_id" \
  --user-name "顯示名稱" \
  [--date YYYY-MM-DD] \
  [--note "備註"]
```

**必填**：`--amount`、`--category`、`--desc`、`--user-id`、`--user-name`
**選填**：`--type`（預設 expense）、`--date`（預設今天）、`--note`

> ⚠️ `--category` 必須是現有分類的精確名稱。先執行 `categories` 查詢。
> 分類匹配規則見 [CATEGORIES-GUIDE.md](CATEGORIES-GUIDE.md)。

**輸出**：
```json
{
  "status": "ok",
  "id": 42,
  "type": "expense",
  "amount": 120,
  "category": "餐飲",
  "description": "拉麵",
  "date": "2026-03-21",
  "month_expense_total": 5230,
  "month_income_total": 0
}
```

---

## categories

查詢可用分類清單。

```bash
bash {baseDir}/scripts/expense.sh categories [--type <expense|income|both>]
```

**輸出**：JSON 陣列，每個元素含 `id`、`name`、`icon`、`applicable_type`。

---

## add-category

新增分類。僅在現有分類完全無法匹配時使用（見 [CATEGORIES-GUIDE.md](CATEGORIES-GUIDE.md)）。

```bash
bash {baseDir}/scripts/expense.sh add-category \
  --name "分類名稱" \
  [--icon "emoji"] \
  [--scope <expense|income|both>]
```

**必填**：`--name`
**選填**：`--icon`、`--scope`（預設 both）

---

## summary

月度收支報表。

```bash
bash {baseDir}/scripts/expense.sh summary \
  [--month YYYY-MM] \
  [--user-id "discord_user_id"]
```

**選填**：`--month`（預設本月）、`--user-id`（預設全部用戶）

**輸出**：含 `month`、`expense_total`、`income_total`、`transaction_count`、`by_category` 陣列。

---

## list

近期交易紀錄。

```bash
bash {baseDir}/scripts/expense.sh list \
  [--days <天數>] \
  [--user-id "discord_user_id"]
```

**選填**：`--days`（預設 7）、`--user-id`（預設全部用戶）

**輸出**：JSON 陣列，每筆含 `id`、`type`、`amount`、`category`、`icon`、`description`、`note`、`user_name`、`date`。

---

## delete

刪除一筆交易紀錄。只能刪除自己的紀錄。

```bash
bash {baseDir}/scripts/expense.sh delete \
  --id <紀錄ID> \
  --user-id "discord_user_id"
```

**必填**：`--id`、`--user-id`

**輸出**：
```json
{
  "status": "ok",
  "deleted": { "id": 42, "type": "expense", "amount": 120, "description": "拉麵", "date": "2026-03-21" }
}
```

---

## update

修改一筆交易紀錄的欄位。只傳需要修改的欄位。

```bash
bash {baseDir}/scripts/expense.sh update \
  --id <紀錄ID> \
  --user-id "discord_user_id" \
  [--amount <正整數>] \
  [--category "分類名稱"] \
  [--desc "品項描述"] \
  [--date YYYY-MM-DD] \
  [--note "備註"] \
  [--type <expense|income>]
```

**必填**：`--id`、`--user-id`
**選填**：至少提供一個要修改的欄位

> `--note ""` 可清除備註。

**輸出**：
```json
{
  "status": "ok",
  "updated": { "id": 42, "type": "expense", "amount": 100, "description": "拉麵", "note": "午餐", "date": "2026-03-21", "category": "餐飲" }
}
```

---

## recurring-add

新增一筆固定開銷（如房租、訂閱服務）。

```bash
bash {baseDir}/scripts/expense.sh recurring-add \
  --name "開銷名稱" \
  --amount <正整數> \
  --category "分類名稱" \
  --user-id "discord_user_id" \
  --user-name "顯示名稱" \
  [--frequency monthly] \
  [--note "備註"]
```

**必填**：`--name`、`--amount`、`--category`、`--user-id`、`--user-name`
**選填**：`--frequency`（預設 monthly）、`--note`

**輸出**：
```json
{
  "status": "ok",
  "recurring": { "id": 1, "name": "房租", "amount": 8000, "category": "居住", "icon": "🏠", "frequency": "monthly", "note": "含管理費", "is_active": true }
}
```

---

## recurring-list

列出固定開銷。

```bash
bash {baseDir}/scripts/expense.sh recurring-list \
  [--user-id "discord_user_id"] \
  [--active-only]
```

**選填**：`--user-id`（預設全部用戶）、`--active-only`（僅啟用中）

**輸出**：JSON 陣列，每筆含 `id`、`name`、`amount`、`category`、`icon`、`frequency`、`note`、`user_name`、`is_active`。

---

## recurring-update

修改一筆固定開銷。只傳需要修改的欄位。

```bash
bash {baseDir}/scripts/expense.sh recurring-update \
  --id <紀錄ID> \
  --user-id "discord_user_id" \
  [--name "新名稱"] \
  [--amount <正整數>] \
  [--category "分類名稱"] \
  [--note "備註"] \
  [--frequency "頻率"] \
  [--active true|false]
```

**必填**：`--id`、`--user-id`
**選填**：至少提供一個要修改的欄位

> `--active false` 停用固定開銷（soft delete）。
> `--note ""` 可清除備註。

**輸出**：
```json
{
  "status": "ok",
  "updated": { "id": 1, "name": "房租", "amount": 9000, "category": "居住", "icon": "🏠", "frequency": "monthly", "note": null, "is_active": true }
}
```

---

## recurring-delete

刪除一筆固定開銷（硬刪除）。只能刪除自己的紀錄。

```bash
bash {baseDir}/scripts/expense.sh recurring-delete \
  --id <紀錄ID> \
  --user-id "discord_user_id"
```

**必填**：`--id`、`--user-id`

**輸出**：
```json
{
  "status": "ok",
  "deleted": { "id": 1, "name": "房租", "amount": 8000, "category": "居住" }
}
```
