# OpenClaw Context 管理

## 自動防護機制

OpenClaw 不會因長時間對話導致 context 爆炸，有三層防護：

### 1. Pruning（修剪）
- 自動移除舊的 tool results
- 只影響記憶體，不動磁碟上的 session 紀錄
- 只修剪 `toolResult` 訊息，user/assistant 訊息不動

### 2. Compaction（壓縮）
- Context 接近 ~40K tokens 時自動觸發
- 摘要舊訊息，保留關鍵資訊（不是直接截斷）
- 移除程序性噪音（確認訊息、暫時錯誤）
- 多輪 debug 迴圈會被壓縮成單一結果

### 3. Memory Flush（記憶沖刷）
- Compaction 前自動觸發一輪靜默 agentic turn
- 提醒 model 把重要事實寫入 `MEMORY.md`
- 防止有價值的資訊在摘要過程中遺失

## 四層記憶架構

| 層級 | 內容 | 生命週期 |
|------|------|----------|
| Bootstrap Files | SOUL.md、USER.md、AGENTS.md、MEMORY.md | 每次 session 開始載入，永久存在 |
| Session Transcript | 完整對話歷史（JSONL） | 重啟後清除（除非用 managed hosting） |
| LLM Context Window | 活躍的對話內容 | 超過上限時觸發 compaction |
| Retrieval Index | 語意搜尋（70% vector + 30% lexical） | SQLite + FTS5 + sqlite-vec |

## 持久記憶

- `MEMORY.md` 是持久知識庫，跨 session 存在
- Daily notes `memory/YYYY-MM-DD.md` 作為活動日誌
- 30 天後可歸檔到 `archives/`

## Session 隔離

`session.dmScope` 控制對話隔離範圍：
- `per-channel-peer`（預設）：每個使用者獨立對話
- `per-channel`：同 channel 內共享 context

## 關鍵原則

> "If it's not written to a file, it doesn't exist."

重要資訊必須寫入磁碟檔案（MEMORY.md），只存在對話中的資訊會在 compaction 時消失。
