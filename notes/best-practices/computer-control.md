# OpenClaw 電腦操控能力

## exec Tool

OpenClaw 透過 `exec` tool 執行 shell 指令，等同完整終端控制：
- 檔案操作（讀寫、搬移、複製）
- 啟動應用程式
- Process 管理
- 排程任務（cron）

其他相關 tool：
- `read` — 讀取檔案
- `write` — 寫入檔案
- `edit` — 修改檔案
- `apply_patch` — 套用 patch
- `process` — Process 管理

## 安全控制（三層）

### 1. Agent 層級

```json5
{
  id: "home",
  tools: {
    allow: ["sessions_send", "read"],
    deny: ["exec", "write"]  // 限制危險操作
  }
}
```

### 2. Exec Approval（執行審批）

三種模式：
- `"deny"` — 禁止所有 exec
- `"allowlist"` — 只允許預先核准的指令
- `"full"` — 允許所有（不建議給對外 agent）

需要審批時會回傳 `"approval-pending"` 狀態。

### 3. Docker Sandbox

```json5
{
  id: "public-agent",
  sandbox: {
    mode: "all",      // 每個 session 都在 sandbox 內執行
    scope: "agent"
  }
}
```

Sandbox 模式：
- `"all"` — 全部 sandbox
- `"rw"` — workspace 以 read/write 掛載
- `"non-main"` — 非主要 session 才 sandbox

## 建議設定

家庭助手場景，建議最小權限：

```json5
// 家庭助手 — 只需要對話，不需要操控電腦
{
  id: "home",
  tools: { deny: ["exec", "write", "edit", "process"] }
}

// 自動化助手 — 需要執行指令但加審批
{
  id: "automation",
  tools: { allow: ["exec", "read", "write"] },
  // 搭配 exec approval = "allowlist"
}
```

## 注意事項

- Sandbox 內的 exec 不會繼承 host 的環境變數
- `requires.bins` 在 host 上檢查，sandbox 內需另外安裝
- 避免給對外 agent 使用 `"full"` exec 權限
