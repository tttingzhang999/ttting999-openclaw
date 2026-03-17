# Skill 部署到 OpenClaw Agent

## 載入 Skill 的四種來源

| 方式 | 路徑 | 優先級 | 可見範圍 |
|------|------|--------|----------|
| Workspace skills | `<workspace>/skills/` | 最高 | 僅該 agent |
| 全域 skills | `~/.openclaw/skills/` | 高 | 所有 agent |
| Bundled skills | OpenClaw 內建 | 中 | 所有 agent |
| extraDirs | openclaw.json 設定 | 最低 | 所有 agent |

同名 skill 衝突時，高優先級覆蓋低優先級。

---

## ~~方法一：Symlink 到 workspace~~（不可用）

> ⚠️ **Symlink 不可用。** OpenClaw 的 skill discovery 會做 realpath 安全檢查，
> 要求解析後的路徑必須在 workspace root 內。Symlink 指向外部 repo 會被靜默忽略，
> 不會報錯也不會載入。（2026-03-17 實測確認）

## 方法一：直接複製到 workspace（推薦）

```bash
# 把 skill 複製到對應 agent 的 workspace
cp -r ~/ting-openclaw/skills/expense ~/.openclaw/workspace-finance/skills/expense

# 更新時重新複製
rm -rf ~/.openclaw/workspace-finance/skills/expense
cp -r ~/ting-openclaw/skills/expense ~/.openclaw/workspace-finance/skills/expense
```

缺點：改了 repo 要手動同步。可以寫 deploy script 自動化。

## 方法二：extraDirs 指向整個 repo

所有 skill 一次載入，但優先級最低。

```json5
// ~/.openclaw/openclaw.json
{
  skills: {
    load: {
      extraDirs: ["/Users/ting/ting-openclaw/skills"]
    }
  }
}
```

## 方法三：全域 skills 目錄

放在 `~/.openclaw/skills/` 下，所有 agent 都看得到。同樣不能用 symlink。

```bash
cp -r ~/ting-openclaw/skills/shared-utils ~/.openclaw/skills/shared-utils
```

---

## 不同 Agent 使用不同 Skill

每個 agent 有獨立的 workspace，workspace 下的 skills 只有該 agent 看得到。

```
~/.openclaw/
├── workspace-home/
│   └── skills/
│       ├── calendar/     ← 只有 home agent
│       └── expense/      ← 只有 home agent
│
├── workspace-study/
│   └── skills/
│       └── study/        ← 只有 study agent
│
└── skills/               ← 全域，所有 agent 共用
    └── shared-utils/
```

對應的 openclaw.json：

```json5
{
  agents: {
    list: [
      { id: "home", workspace: "~/.openclaw/workspace-home" },
      { id: "study", workspace: "~/.openclaw/workspace-study" },
      { id: "finance", workspace: "~/.openclaw/workspace-finance" }
    ]
  }
}
```

---

## 載入後生效

- 開啟新 session（`/new`），skill 會在新 session 開始時重新載入
- 或啟用 `skills.load.watch: true`（預設啟用），檔案變更時自動偵測更新

注意：skill 在 session 開始時快照載入，修改後需要新 session 才會生效。

---

## 這個 Repo 的部署流程

```bash
# 1. 建立 agent（如果還沒建）
openclaw agents add --id finance --workspace ~/.openclaw/workspace-finance

# 2. 複製 skill 到 workspace（不能用 symlink）
cp -r ~/Documents/coding/ttting999-openclaw/skills/expense ~/.openclaw/workspace-finance/skills/expense

# 3. 驗證（注意：CLI 只掃 main workspace，per-agent 要用 agent 指令確認）
openclaw agent --agent finance --message "列出你有哪些 skill"

# 4. 設定 auto approve（免手動批准 exec）
openclaw approvals allowlist add --agent finance "*/skills/expense/scripts/*"
```

## 注意事項

- `openclaw skills list` 只掃 main workspace，不顯示 per-agent workspace skills，但 runtime 會正確載入
- Skill 在 session 開始時快照載入，部署後需要開新 session 才生效
- 修改 repo 後記得重新 `cp -r` 到 workspace
