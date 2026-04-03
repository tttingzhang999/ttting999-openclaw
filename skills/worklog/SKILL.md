---
name: worklog
description: Captures work items (tasks, notes, todos) from natural language input. Tracks status, priority, and project association. Use when the user mentions what they are working on, what needs to be done, task status updates, or asks about pending items.
---

# Worklog — 工作事項追蹤

記錄使用者的工作事項、待辦、筆記。支援自然語言輸入，自動分類並追蹤狀態。

## DB 操作

**所有資料庫操作透過 CLI wrapper，禁止直接執行 psql 或 raw SQL：**

```bash
bash {baseDir}/scripts/worklog.sh <command> [options]
```

---

## 自然語言模式（主要使用流程）

使用者通常 raw 輸入目前在做的事或待辦事項。例如：

```
現在在寫 API 文件，等等要跟 PM 開會討論需求，明天之前要完成 code review
```

### Step 1 — 解析

從自然語言提取每個工作事項：
- **content**：事項描述
- **type**：自動判斷
  - `note` — 正在做的事、已完成的描述（「在寫…」「剛完成…」）
  - `todo` — 需要做的事（「要…」「需要…」「待…」「之前要…」）
  - `task` — 有明確 deadline 或可衡量的工作項目
- **project**：若能從描述推斷對應的 timetrack project，自動填入
- **priority**：預設 `normal`，除非使用者明確表達緊急性
- **due_date**：若提到時間（「明天之前」「週五前」），轉換為 YYYY-MM-DD

### Step 2 — 確認並寫入

解析後直接批次寫入，回覆簡潔確認：

```
✓ 已記錄 3 筆
- [note] 寫 API 文件
- [todo] 跟 PM 開會討論需求
- [task] 完成 code review (due: 2026-04-04)
```

不需要使用者二次確認（與 timetrack 不同，worklog 是低風險操作）。

---

## Commands

### 1. add — 新增工作事項

```bash
bash {baseDir}/scripts/worklog.sh add \
  --content "事項描述" \
  [--type task|note|todo] \
  [--project <project_id>] \
  [--priority low|normal|high|urgent] \
  [--due YYYY-MM-DD] \
  [--tags "tag1,tag2"]
```

- `--content` 必填
- `--type` 預設 `note`

### 2. list — 列出工作事項

```bash
bash {baseDir}/scripts/worklog.sh list \
  [--status open|in_progress|done|cancelled] \
  [--type task|note|todo] \
  [--project <project_id>] \
  [--days <N>] \
  [--limit <N>]
```

預設列出最近 7 天、所有狀態。

### 3. done — 完成事項

```bash
bash {baseDir}/scripts/worklog.sh done --id <int>
```

將 status 設為 `done`，記錄 completed_at。

### 4. update — 修改事項

```bash
bash {baseDir}/scripts/worklog.sh update \
  --id <int> \
  [--content "新描述"] \
  [--status open|in_progress|done|cancelled] \
  [--priority low|normal|high|urgent] \
  [--project <project_id>] \
  [--due YYYY-MM-DD] \
  [--tags "tag1,tag2"]
```

### 5. delete — 刪除事項

```bash
bash {baseDir}/scripts/worklog.sh delete --id <int>
```

刪除前向使用者確認。

### 6. summary — 統計摘要

```bash
bash {baseDir}/scripts/worklog.sh summary [--days <N>]
```

回傳各狀態數量、近期活動、逾期項目。

---

## 行為指引

- 使用者問「我還有什麼事要做」→ 執行 `list --status open --status in_progress`
- 使用者問「今天做了什麼」→ 執行 `list --days 1`
- 使用者說「XXX 完成了」→ 用 `list` 找到對應項目，執行 `done`
- 使用者說「現在在做 XXX」→ 新增 note，並將對應的 todo/task 更新為 `in_progress`

## 規則

- 回應使用繁體中文
- **禁止直接執行 psql 或任何 raw SQL，只能透過 worklog.sh 操作資料庫**
- 低風險操作（新增 note/todo）直接寫入，不用二次確認
- 刪除操作必須先確認

## Schema Reference

DB 結構詳見 [SCHEMA.md](SCHEMA.md)。
