# OpenClaw Context 管理

## 自動防護機制

OpenClaw 不會因長時間對話導致 context 爆炸，有三層防護：

### 1. Pruning（修剪）
- 自動移除舊的 tool results
- 只影響記憶體，不動磁碟上的 session 紀錄
- 只修剪 `toolResult` 訊息，user/assistant 訊息不動

### 2. Compaction（壓縮）
- Context 接近 model context window 上限時自動觸發（例如 200K model 扣除 `reserveTokensFloor` 預設 20K，約在 ~180K tokens 時觸發）
- 摘要舊訊息，保留關鍵資訊（不是直接截斷）

### 3. Memory Flush（記憶沖刷）
- Compaction 前自動觸發一輪靜默 agentic turn
- 提醒 model 把重要事實寫入 `MEMORY.md`
- 防止有價值的資訊在摘要過程中遺失

## 四層記憶架構

| 層級 | 內容 | 生命週期 |
|------|------|----------|
| Bootstrap Files | SOUL.md、USER.md、AGENTS.md、MEMORY.md、TOOLS.md | 每次 session 開始載入，永久存在 |
| Session Transcript | 完整對話歷史（JSONL） | 持久保存在磁碟（`~/.openclaw/agents/<agentId>/sessions/*.jsonl`） |
| LLM Context Window | 活躍的對話內容 | 超過上限時觸發 compaction |
| Retrieval Index | 語意搜尋（70% vector + 30% lexical） | SQLite + FTS5 + sqlite-vec |

## 持久記憶

- `MEMORY.md` 是持久知識庫，跨 session 存在
- Daily notes `memory/YYYY-MM-DD.md` 作為活動日誌
- 30 天後可歸檔到 `archives/`

## Session 隔離

`session.dmScope` 控制對話隔離範圍：
- `main`（預設）：所有 DM 共用主 session，保持連續性
- `per-peer`：每個對話對象獨立 session
- `per-channel-peer`：每個 channel + 使用者獨立對話（多使用者場景推薦）
- `per-account-channel-peer`：最細粒度，按 account + channel + 使用者隔離

## 關鍵原則

> "If it's not written to a file, it doesn't exist."

重要資訊必須寫入磁碟檔案（MEMORY.md），只存在對話中的資訊會在 compaction 時消失。
