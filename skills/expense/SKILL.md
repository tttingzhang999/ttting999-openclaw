---
name: expense
description: Records income and expenses to PostgreSQL, categorizes transactions, and generates summaries. Use when users mention spending, buying, earning, income, budgets, or ask for expense reports.
---

# Expense Tracker

## 觸發條件

當使用者提到記帳、花費、收入、買東西、報表、月報相關的請求時觸發。

## 指令

### Step 1: 識別用戶

從對話 context 取得發訊者的 Discord 顯示名稱和唯一 ID。這兩個值會作為 `--user-id` 和 `--user-name` 傳入所有指令。

### Step 2: 解析輸入

從用戶訊息提取：
- **類型**: expense（預設）或 income
- **金額**: 正整數（TWD）
- **品項**: 描述文字
- **分類**: 匹配現有分類
- **日期**: 未指定則今天，用戶說「昨天」則推算日期

圖片處理：用戶有明確給金額就用，沒給就嘗試從圖片 OCR 提取金額和品項。

### Step 3: 查詢分類

```bash
bash {baseDir}/scripts/expense.sh categories --type <expense|income>
```

自動匹配最適合的分類。找不到 → 詢問使用者要選現有的還是新增。

新增分類：
```bash
bash {baseDir}/scripts/expense.sh add-category --name "寵物" --icon "🐕" --scope expense
```

### Step 4: 確認

以下情況必須先回覆摘要等使用者確認再寫入：
- 金額 ≥ 1000
- 從圖片 OCR 提取的資訊

摘要格式：
> 📝 類型：支出 | 金額：30 元 | 品項：立可帶 | 分類：日用品 | 日期：2026-03-17

金額 < 1000 且非 OCR 時可直接寫入，不需等確認。

### Step 5: 寫入

```bash
bash {baseDir}/scripts/expense.sh add \
  --type expense --amount 30 --category "日用品" \
  --desc "立可帶" --user-id "459425570162475009" \
  --user-name "ttting999"
```

可選參數：`--date YYYY-MM-DD`、`--note "備註"`

### Step 6: 回覆

顯示：✓ 已記錄，並附上本月累計支出/收入（從回傳 JSON 的 `month_expense_total` 和 `month_income_total` 取得）。

## 查詢與報表

月報：
```bash
bash {baseDir}/scripts/expense.sh summary --month 2026-03 --user-id "459425570162475009"
```

近期紀錄：
```bash
bash {baseDir}/scripts/expense.sh list --days 7 --user-id "459425570162475009"
```

查詢時預設 filter 當前用戶的紀錄。用戶明確要求「全部」時省略 `--user-id`。

更多 schema 細節見 [SCHEMA.md](SCHEMA.md)。

## 規則

- 回應使用繁體中文
- 貨幣預設 TWD，金額正整數
- 分類不存在時詢問使用者，不自行猜測
- **禁止直接執行 psql 或任何 raw SQL，只能透過 expense.sh 操作資料庫**
