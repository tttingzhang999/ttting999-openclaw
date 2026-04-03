---
name: timetrack
description: Tracks personal work hours across 3 layers (actual time, internal credit, client billing) per project and epic. Logs time entries, recaps current work items, batch-updates internal/client reference numbers, and generates ratio reports with work item classification. Use when the user mentions logging work time, tracking hours, recapping work items, or analyzing time-to-revenue efficiency.
---

# Timetrack — 個人工時追蹤

> 公司對外以「人天」(person-day) 計費，但內部以小時追蹤（精度 0.1h）。
> 轉換：`client_days = internal_hours / hours_per_day`（預設 8）。

## 3-Layer 填入時機

| Layer | 欄位 | 何時填入 |
|-------|------|---------|
| L1 | actual_hours | 每日（必填） |
| L2 | internal_hours | 每日（選填，有就一起填；0 = 不報公司） |
| L3 | client_days | 結案後，透過 `ref` 批次填入 |

## DB 操作

**所有資料庫操作透過 CLI wrapper，禁止直接執行 psql 或 raw SQL：**

```bash
bash {baseDir}/scripts/timetrack.sh <command> [options]
```

---

## 日報模式（主要使用流程）

使用者通常一次貼入一天的時間記錄，格式自由。例如：

```
今日時間開銷
- GAIA2.0
otel 文件撰寫 - 1h / 公司 1.5h
API 測試 - 1h / 公司 2h
- CTBC-EAO
API 測試元件導入評估 - 1h / 公司 1h
- 其他
eks internal service 除錯 - 0.5h / 公司 0.5h
文章撰寫 - 1h / 公司 0h
```

### Step 1 — 解析

從自然語言提取每筆 entry 的：
- project（`-` 開頭的行通常是專案名）
- task（描述文字）
- actual_hours（L1，`1h`, `0.5h`, `30m`, `2小時`, `半小時` → 十進位小時）
- internal_hours（L2，若使用者有寫「公司 Xh」）
- epic（若有提供）

### Step 2 — Project 對應

1. 執行 `timetrack.sh project list` 取得現有 projects
2. 用 LLM 判斷做模糊比對（如 `GAIA2.0` = `gaia2`、`CTBC-EAO` = `ctbc-eao`）。不要用寫死的 alias 邏輯，每次根據現有 project 清單和使用者輸入做智慧判斷。
3. 「其他」→ 對應 `misc` project
4. 找不到對應的 project → 自動 `project add` 建立（id 用 kebab-case, name 用使用者原始輸入）

### Step 3 — 確認表格

輸出解析結果讓使用者確認。表格欄位依提供的資料動態調整：

**有 L2 時：**
```
| # | 專案 | Task | 實際(L1) | 公司(L2) | ⚠️ |
|---|------|------|---------|---------|-----|
| 1 | gaia2 | otel 文件撰寫 | 1h | 1.5h | 缺 epic |
| 2 | gaia2 | API 測試 | 1h | 2h | 缺 epic |
| 3 | ctbc-eao | API 測試元件導入評估 | 1h | 1h | 缺 epic |
| 4 | misc | eks internal service 除錯 | 0.5h | 0.5h | 缺 epic |
| 5 | misc | 文章撰寫 | 1h | 0h | 缺 epic |
⚠️ 新專案 ctbc-eao 將自動建立
合計：4.5h 實際 / 5h 公司
```

**只有 L1 時（省略 L2 欄）：**
```
| # | 專案 | Task | 實際(L1) | ⚠️ |
|---|------|------|---------|-----|
| 1 | gaia2 | otel 文件撰寫 | 1h | 缺 epic |
```

⚠️ 欄位提醒缺少的重要資訊（epic 為必提醒項）。

### Step 4 — 使用者確認或修改

- 使用者說「OK」或「確認」→ 進入 Step 5
- 使用者複製表格修改後貼回 → 重新解析修改版，再次確認

### Step 5 — 批次寫入

1. 自動建立不存在的 projects
2. 逐筆呼叫 `timetrack.sh log`
3. 完成後顯示：`✓ 已記錄 N 筆，共 X.Xh`

---

## Commands

解析 `$ARGUMENTS` 判斷要執行哪個命令。含時間值時預設走日報模式。

---

### 1. log — 記錄工時

```bash
bash {baseDir}/scripts/timetrack.sh log \
  --project <project_id> \
  --task "任務描述" \
  --hours <decimal> \
  [--internal-hours <decimal>] \
  [--epic "epic"] \
  [--subtask "subtask"] \
  [--date YYYY-MM-DD] \
  [--notes "備註"]
```

- `--hours`（L1）：必填，> 0
- `--internal-hours`（L2）：選填，>= 0（0 = 不報公司時數）
- 不帶 `--internal-hours` 時，L2 = NULL（之後可用 ref 補填）

---

### 2. recap — 近期工作概覽

```bash
bash {baseDir}/scripts/timetrack.sh recap \
  --project <project_id> \
  [--days <N>] \
  [--epic "epic"]
```

預設最近 7 天。顯示：entries 列表、總實際工時、缺少 L2/L3 的數量、按 epic 小計。

---

### 3. ref — 批次填入客戶人天（結案後）

主要用途：專案結案後，批次填入 L3（client_days）。也可補填遺漏的 L2。

```bash
bash {baseDir}/scripts/timetrack.sh ref \
  --project <project_id> \
  --epic "epic" \
  [--start-date YYYY-MM-DD] \
  [--end-date YYYY-MM-DD] \
  [--internal-hours <decimal>] \
  [--client-days <decimal>]
```

**未指定日期時**：自動選取該 epic 下所有對應欄位為 NULL 的 entries。
按 actual_hours 比例分配，最後一筆吸收捨入差。

> 注意：只更新 NULL 的 entries。已有值的不會被覆蓋。若需重新分配，先用 `edit` 清除既有值。

---

### 4. report — 比率分析 + 分類

```bash
bash {baseDir}/scripts/timetrack.sh report \
  --project <project_id> \
  [--start-date YYYY-MM-DD] \
  [--end-date YYYY-MM-DD]
```

輸出 per-epic 比率 + 分類標籤。分類閾值見 [reference/classification.md](reference/classification.md)：

| Type | Credit Ratio | Revenue Ratio | 建議 |
|------|-------------|---------------|------|
| 黃金工項 | > 2.0 | > 0.3 d/h | 多接、主導 |
| 政治型 | > 2.0 | < 0.15 d/h | 升遷有用 |
| 苦工型 | < 1.2 | < 0.15 d/h | 少接 |
| 商業槓桿 | 1.2–2.0 | > 0.3 d/h | 往 solution 走 |

資料不足的 epic 標記「資料不足」，不做分類。

---

### 5. project — 管理專案

**新增/更新：**
```bash
bash {baseDir}/scripts/timetrack.sh project add \
  --id <project_id> \
  --name "專案名稱" \
  [--client "客戶名稱"] \
  [--hours-per-day <decimal>]
```

**列表：**
```bash
bash {baseDir}/scripts/timetrack.sh project list
```

---

### 6. edit — 修改工時記錄

先用 recap 找到 entry ID，確認後修改：

```bash
bash {baseDir}/scripts/timetrack.sh edit \
  --id <entry_id> \
  [--task "新描述"] \
  [--hours <decimal>] \
  [--epic "epic"] \
  [--subtask "subtask"] \
  [--date YYYY-MM-DD] \
  [--internal-hours <decimal>] \
  [--client-days <decimal>] \
  [--notes "備註"]
```

---

### 7. delete — 刪除工時記錄

先用 recap 找到 entry ID，**確認後**刪除：

```bash
bash {baseDir}/scripts/timetrack.sh delete --id <entry_id>
```

刪除前務必向使用者確認。

---

## 行為指引

- **Project 對應**：每次用 `project list` 取得清單，以 LLM 判斷做模糊比對。不寫死 alias。
- **自動建 project**：找不到對應時，自動建立（id kebab-case, name 保留原始輸入）。
- **「其他」→ `misc`**：首次使用時自動建立 misc project。
- **單一 project 時**：自動使用，不用每次問。
- **Epic 提醒**：使用者沒提供 epic 時，在確認表格的 ⚠️ 欄位提醒。

## 規則

- 回應使用繁體中文，資料用表格呈現
- 時間精度 0.1 小時
- **禁止直接執行 psql 或任何 raw SQL，只能透過 timetrack.sh 操作資料庫**
- 刪除操作必須先確認

## Schema Reference

DB 結構與 3-Layer Model 詳見 [SCHEMA.md](SCHEMA.md)。
