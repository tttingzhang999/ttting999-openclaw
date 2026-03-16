# Skill 部署到 OpenClaw Agent

## 載入 Skill 的三種方式

| 方式 | 路徑 | 優先級 | 可見範圍 |
|------|------|--------|----------|
| Workspace skills | `<workspace>/skills/` | 最高 | 僅該 agent |
| 全域 skills | `~/.openclaw/skills/` | 中 | 所有 agent |
| extraDirs | openclaw.json 設定 | 低 | 所有 agent |
| Bundled skills | OpenClaw 內建 | 最低 | 所有 agent |

同名 skill 衝突時，高優先級覆蓋低優先級。

---

## 方法一：Symlink 到 workspace（推薦）

好處：repo 改了 SKILL.md，agent 下次 session 馬上生效。

```bash
# 把 skill 連結到對應 agent 的 workspace
ln -s ~/ting-openclaw/skills/calendar ~/.openclaw/workspace-home/skills/calendar
ln -s ~/ting-openclaw/skills/expense  ~/.openclaw/workspace-finance/skills/expense
ln -s ~/ting-openclaw/skills/study    ~/.openclaw/workspace-study/skills/study

# 所有 agent 共用的 skill 放全域
ln -s ~/ting-openclaw/skills/shared-utils ~/.openclaw/skills/shared-utils
```

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

## 方法三：直接複製

不推薦，因為改了 repo 還要手動同步。

```bash
cp -r ~/ting-openclaw/skills/calendar ~/.openclaw/workspace-home/skills/
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

- 重啟 gateway，或
- 請 agent「refresh skills」

不需要其他安裝步驟。

---

## 這個 Repo 的部署流程

```bash
# 1. 建立 agent（如果還沒建）
openclaw agents add home
openclaw agents add study
openclaw agents add finance

# 2. 用 symlink 分配 skill
ln -s ~/ting-openclaw/skills/calendar ~/.openclaw/workspace-home/skills/calendar
ln -s ~/ting-openclaw/skills/expense  ~/.openclaw/workspace-finance/skills/expense
ln -s ~/ting-openclaw/skills/study    ~/.openclaw/workspace-study/skills/study

# 3. 驗證
openclaw agents list
# 請各 agent 測試：「列出你有哪些 skill」
```
