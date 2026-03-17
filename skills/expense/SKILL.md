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
- **品項**: 描述文字（CLI 參數為 `--desc`，不是 --item）
- **分類**: 匹配現有分類
- **日期**: 未指定則今天，用戶說「昨天」則推算日期

圖片處理：用戶有明確給金額就用，沒給就嘗試從圖片 OCR 提取金額和品項。

### Step 3: 查詢分類

> ⚠️ **必須在 add 之前執行此步驟** — 不可跳過。先查分類，確認分類名稱存在後才能呼叫 add。

```bash
bash {baseDir}/scripts/expense.sh categories --type <expense|income>
```

自動匹配最適合的分類。找不到 → 直接用 add-category 新增最合理的分類，不需詢問使用者。

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

回覆內容：`✓ {品項} {金額}元（{分類}）— 本月累計支出 {month_expense_total} 元`

#### Discord（有討論串功能時）

透過每日討論串回覆，將同一天的記帳紀錄集中在一個 thread 裡：

**6a: 搜尋今天的日期訊息**

用 discord `searchMessages` 搜尋記帳頻道中是否已有今天的日期錨點訊息：
- content: `📅 {YYYY-MM-DD}`（例如 `📅 2026-03-17`）
- 頻道和 Guild ID 見 TOOLS.md

**6b: 建立日期訊息（若不存在）**

搜尋結果為空時，用 discord `sendMessage` 在記帳頻道發送 `📅 {YYYY-MM-DD}`。記下回傳的 message ID。

**6c: 建立或取得討論串**

用 discord `threadCreate` 在日期訊息上建立討論串：
- messageId:（6a 搜到或 6b 建立的 message ID）
- name: `{M/D} 記帳`（例如 `3/17 記帳`，月日不補零）

討論串已存在時 Discord 會回傳現有的。記下討論串的 channel ID。

**6d: 在討論串中回覆**

用 discord `threadReply` 在討論串中發送記帳確認訊息。

#### 其他平台（LINE 等）

直接回覆記帳確認訊息，不需要討論串流程。

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
- 分類不存在時，根據品項自動新增最合理的分類
- **禁止直接執行 psql 或任何 raw SQL，只能透過 expense.sh 操作資料庫**
