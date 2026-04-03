---
name: expense
description: Records income and expenses to PostgreSQL, categorizes transactions, manages recurring fixed costs, and generates summaries. Use when users mention spending, buying, earning, income, budgets, expense reports, fixed costs, subscriptions, or recurring payments.
---

# Expense Tracker

## 觸發條件

當使用者提到記帳、花費、收入、買東西、報表、月報、固定開銷、月費、訂閱、房租等相關的請求時觸發。

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
- **備註**: 餐別、地點等補充資訊（CLI 參數為 `--note`）

圖片處理：用戶有明確給金額就用，沒給就嘗試從圖片 OCR 提取金額和品項。

### Step 3: 匹配分類

> ⚠️ **必須在 add 之前執行此步驟** — 不可跳過。

1. 查詢現有分類（見 [COMMANDS.md](COMMANDS.md) 的 `categories` 指令）
2. 按照 [CATEGORIES-GUIDE.md](CATEGORIES-GUIDE.md) 匹配最適合的分類，並決定 `--note` 值
3. **嚴禁**為了「更精確」而建立細項分類（午餐、飲食、晚餐等都應歸入「餐飲」+ note）
4. 只有品項完全無法歸入任何現有分類時，才用 `add-category` 新增

### Step 4: 確認

以下情況必須先回覆摘要等使用者確認再寫入：
- 金額 ≥ 5000
- 從圖片 OCR 提取的資訊

摘要格式：
> 📝 類型：支出 | 金額：30 元 | 品項：立可帶 | 分類：日用品 | 日期：2026-03-17

金額 < 1000 且非 OCR 時可直接寫入，不需等確認。

### Step 5: 寫入

使用 `add` 指令記錄交易。完整語法見 [COMMANDS.md](COMMANDS.md)。

### Step 6: 回覆

回覆內容：`✓ {品項} {金額}元（{分類}）— 本月累計支出 {month_expense_total} 元`

#### Discord（有討論串功能時）

透過每日討論串回覆，將同一天的記帳紀錄集中在一個 thread 裡：

**6a: 優先尋找既有當日討論串**

先用 discord `thread-list` 檢查主頻道底下是否已存在當日討論串：
- parent channel: 記帳主頻道
- thread name: `{M/D} 記帳`（例如 `3/17 記帳`，月日不補零）
- 若找到，直接使用該 thread 的 channel ID，跳到 6d

**6b: 搜尋今天的日期訊息（僅在找不到 thread 時）**

用 discord `search` 搜尋記帳頻道中是否已有今天的日期錨點訊息：
- content: `📅 {YYYY-MM-DD}`（例如 `📅 2026-03-17`）
- 頻道和 Guild ID 見 TOOLS.md

**6c: 建立日期訊息與討論串（若仍不存在）**

若沒有既有 thread：
- 搜尋結果有日期訊息 → 用該 message ID 建立 thread
- 搜尋結果為空 → 先在記帳頻道發送 `📅 {YYYY-MM-DD}`，再用新 message ID 建立 thread

用 discord `thread-create` 在日期訊息上建立討論串：
- messageId:（6b 搜到或剛建立的 message ID）
- name: `{M/D} 記帳`

記下討論串的 channel ID。

**6d: 只在討論串中回覆**

用 discord `thread-reply` 在討論串中發送記帳確認訊息。
若 thread 已存在或成功建立，主頻道不要再發任何確認文字。

#### 其他平台（LINE 等）

直接回覆記帳確認訊息，不需要討論串流程。

## 刪除紀錄

1. 先用 `list` 查出紀錄，確認要刪除的 ID
2. 告知使用者即將刪除的紀錄內容，等確認
3. 執行 `delete`（見 [COMMANDS.md](COMMANDS.md)）

回覆：`✓ 已刪除：{品項} {金額}元（{日期}）`

## 修改紀錄

1. 先用 `list` 查出紀錄，確認要修改的 ID
2. 告知使用者修改前後的差異，等確認
3. 執行 `update`，只傳需要改的欄位（見 [COMMANDS.md](COMMANDS.md)）

回覆：`✓ 已修改 #{id}：{修改內容摘要}`

## 查詢與報表

使用 `summary`（月報）或 `list`（近期紀錄）。完整語法見 [COMMANDS.md](COMMANDS.md)。

查詢時預設 filter 當前用戶的紀錄。用戶明確要求「全部」時省略 `--user-id`。

更多 schema 細節見 [SCHEMA.md](SCHEMA.md)。

## 固定開銷管理

當使用者要新增、查看、修改或刪除固定開銷（月租、訂閱、電信費等）時使用。

### 新增固定開銷

1. 解析品項名稱、金額、分類
2. 匹配分類（同一般記帳的分類匹配規則）
3. 執行 `recurring-add`（見 [COMMANDS.md](COMMANDS.md)）
4. 回覆：`✓ 已新增固定開銷：{名稱} {金額}元/月（{分類}）`

### 查看固定開銷

使用 `recurring-list`，預設 filter 當前用戶。

回覆格式（列表）：
```
📋 固定開銷清單：
1. 房租 8,000元/月（居住 🏠）
2. Spotify 149元/月（娛樂 🎮）
合計：8,149元/月
```

### 修改/停用固定開銷

1. 先用 `recurring-list` 確認 ID
2. 告知使用者修改內容，等確認
3. 執行 `recurring-update`
4. 停用用 `--active false`，恢復用 `--active true`

### 刪除固定開銷

1. 先用 `recurring-list` 確認 ID
2. 告知使用者即將刪除的項目，等確認
3. 執行 `recurring-delete`（硬刪除，無法恢復）

## 規則

- 回應使用繁體中文
- 貨幣預設 TWD，金額正整數
- 分類匹配嚴格遵循 [CATEGORIES-GUIDE.md](CATEGORIES-GUIDE.md)，優先使用現有分類 + `--note`
- **禁止直接執行 psql 或任何 raw SQL，只能透過 expense.sh 操作資料庫**
- **用戶名稱對應**：以下 Discord 帳號皆為同一人「張碩庭」，`--user-name` 一律填 `張碩庭`：
  - Discord ID `459425570162475009`（ttting999）
  - Discord ID `1482373772072845495`（ting-openclaw）
