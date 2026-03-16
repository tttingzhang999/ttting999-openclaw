# OpenClaw 多 Agent 設定

## 概念

每個 agent 是完全獨立的「大腦」，擁有：
- 獨立 Workspace（`~/.openclaw/workspace-<agentId>/`）
- 獨立 Session store（`~/.openclaw/agents/<agentId>/sessions/`）
- 獨立人格設定（SOUL.md、AGENTS.md、USER.md）
- 獨立 Tool 權限
- 獨立 Auth profiles

## 建立 Agent

```bash
# CLI 方式（推薦）
openclaw agents add --id home --workspace ~/.openclaw/workspace-home
openclaw agents add --id study --workspace ~/.openclaw/workspace-study
openclaw agents add --id finance --workspace ~/.openclaw/workspace-finance

# 列出所有 agent
openclaw agents list

# 刪除 agent
openclaw agents delete <name>
```

也可以在 `~/.openclaw/openclaw.json` 手動設定：

```json5
{
  agents: {
    list: [
      { id: "home", default: true, workspace: "~/.openclaw/workspace-home" },
      { id: "study", workspace: "~/.openclaw/workspace-study" },
      { id: "finance", workspace: "~/.openclaw/workspace-finance" }
    ]
  }
}
```

## Agent 身份設定

```bash
openclaw agents set-identity --agent home --name "家庭助手" --emoji "🏠"
openclaw agents set-identity --agent study --name "學習助手" --emoji "📚"
```

或在 config 中：

```json5
{
  id: "home",
  workspace: "~/.openclaw/workspace-home",
  identity: {
    name: "家庭助手",
    emoji: "🏠",
    theme: "friendly family assistant"
  }
}
```

## Agent 權限控制

每個 agent 可獨立設定 tool 存取權限：

```json5
{
  id: "home",
  tools: {
    allow: ["sessions_send", "sessions_list", "read"],
    deny: ["exec", "write"]  // 家庭助手不需要執行指令
  }
}
```
