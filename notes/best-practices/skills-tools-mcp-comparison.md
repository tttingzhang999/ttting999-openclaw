# OpenClaw Skill / Tool / AgentSkills / MCP 差異比較

## 一句話總結

| 概念 | 一句話 |
|------|--------|
| **OpenClaw Tool** | 內建的低階能力（exec、read、write、browser） |
| **OpenClaw Skill** | 用 Markdown 教 agent 怎麼組合 tool 完成任務 |
| **AgentSkills (skills.sh)** | 跨平台的開放標準格式，OpenClaw skill 就是這個格式 |
| **MCP Tool** | 透過 protocol 連接外部服務的結構化 API |

---

## 架構關係圖

```
Agent 收到使用者訊息
│
├── 內建 Tools（read, write, exec, browser...）     ← 基礎能力
├── Skills（SKILL.md 指令）                          ← 教 agent 怎麼用 tools
└── MCP Tools（外部服務連接）                         ← Notion, Google, Slack...

三者同時可用，agent 自行判斷用哪個
```

---

## 1. OpenClaw Tools — 基礎建設

Agent 能做什麼事的底層能力，由 OpenClaw 內建提供。

| 類別 | Tools | 用途 |
|------|-------|------|
| 檔案系統 | read, write, edit, apply_patch | 讀寫檔案 |
| 執行 | exec, bash, process | 跑 shell 指令 |
| 瀏覽器 | browser, canvas | 網頁操作 |
| 網路 | web_fetch | 抓取網頁內容 |
| 排程 | cron, webhooks | 定時任務 |

**特性**：
- 永遠可用（可透過 allow/deny 設定權限）
- 不需安裝
- 在 sandbox 內執行時受限於容器環境

---

## 2. OpenClaw Skills — 高階組合指令

用 SKILL.md（Markdown）告訴 agent「遇到某類任務時，怎麼組合 tools 來完成」。

**類比**：Tool 是廚具，Skill 是食譜。

```markdown
---
name: family_expense
description: Track household expenses
---

# 記帳 Skill

當使用者說「記帳」時：
1. 用 read 讀取今天的記帳檔
2. 解析使用者輸入的金額和分類
3. 用 write 寫入新的記錄
4. 回覆確認
```

**載入方式**：
- 不是全部注入 prompt，而是**選擇性載入**相關 skill
- 先載入 metadata（~100 tokens），啟動時才載入完整指令

**來源**：workspace/skills > ~/.openclaw/skills > bundled skills

---

## 3. AgentSkills (skills.sh / agentskills.io) — 開放標準

**OpenClaw Skill 就是 AgentSkills 格式**。AgentSkills 是跨平台的開放規範。

### 支援的平台

Claude Code、OpenClaw、Cursor、GitHub Copilot、VS Code、Goose、Windsurf、Gemini CLI、Roo Code、Trae

### 規範重點

```yaml
---
name: my-skill            # 必填，1-64 字元，kebab-case
description: 做什麼用的    # 必填，1-1024 字元
license: Apache-2.0       # 選填
compatibility: 環境需求    # 選填
metadata:                  # 選填，任意 key-value
  author: org
  version: 1.0.0
allowed-tools: exec read   # 選填（實驗性），預核准的 tools
---

# Markdown 指令（建議 < 500 行）
```

### 目錄結構

```
skill-name/
├── SKILL.md          # 必要
├── scripts/          # 選填：可執行腳本
├── references/       # 選填：參考文件
└── assets/           # 選填：模板、資料
```

### 與 OpenClaw 的關係

- OpenClaw **完整實作** AgentSkills 規範
- 在 OpenClaw 寫的 skill，**不改任何東西**就能發布到 skills.sh，在 Claude Code、Cursor 等平台上使用
- OpenClaw 的小限制：frontmatter parser 只支援**單行** key（不支援多行 YAML）

### 發布

- `skills.sh` — 主要的 skill 分發平台
- `ClawHub (clawhub.com)` — OpenClaw 專屬的 skill registry

---

## 4. MCP Tools — 外部服務連接器

Model Context Protocol，Anthropic 2024 年底發布的開放協議，定義 AI 應用如何連接外部資料源和工具。

### 在 OpenClaw 中的角色

OpenClaw 是 **MCP client**，可以連接任何 MCP server。

### 設定方式

在 `~/.openclaw/openclaw.json`：

```json5
{
  mcpServers: {
    "notion": {
      command: "npx",
      args: ["-y", "@notionhq/notion-mcp-server"],
      env: { "NOTION_API_KEY": "secret_xxx" }
    },
    "google-calendar": {
      command: "node",
      args: ["/path/to/google-calendar-mcp/index.js"]
    }
  }
}
```

### MCP vs Skill

| | Skill | MCP Tool |
|---|---|---|
| 格式 | Markdown 指令 | Server 程式（JS/Python/Go） |
| 安裝 | 放檔案就好 | 需要跑 server process |
| 維護 | 改 Markdown | 改程式碼 |
| 能力 | 教 agent 組合現有 tool | 提供全新的外部能力 |
| 適合 | 流程編排、任務指引 | 連接外部 API（Notion、Google、Slack） |

### 共存

三者完全可以同時使用：

```
你：「幫我把今天花的 300 元午餐記到 Notion」

Agent 推理：
├── 啟動 expense skill（知道記帳流程）
├── 使用 MCP notion tool（寫入 Notion 資料庫）
└── 使用內建 write tool（更新本地記帳檔）
```

---

## 決策指南：什麼時候用什麼

| 需求 | 用什麼 |
|------|--------|
| 教 agent 一套流程 | **Skill**（寫 SKILL.md） |
| 連接外部服務（Notion、Google Calendar） | **MCP Tool**（裝 MCP server） |
| 讓 agent 跑指令、讀寫檔案 | **內建 Tool**（已內建，設定權限即可） |
| 想讓 skill 跨平台使用 | 遵循 **AgentSkills 規範**，發布到 skills.sh |

---

## 你的家庭助手場景

```
skills/
├── calendar/SKILL.md     ← Skill：教 agent 日程管理流程
├── expense/SKILL.md      ← Skill：教 agent 記帳流程
└── study/SKILL.md        ← Skill：教 agent 學習助手流程

openclaw.json mcpServers:
├── notion                ← MCP：連接 Notion 資料庫（記帳、筆記）
├── google-calendar       ← MCP：連接 Google Calendar（日程）
└── (未來) line           ← MCP：連接 LINE Messaging API

內建 tools:
├── exec                  ← 執行腳本（如有需要）
├── read/write            ← 本地檔案操作
└── web_fetch             ← 查詢網頁資訊
```

---

## 參考來源

- 官方 Skills 文件：docs.openclaw.ai/tools/skills
- AgentSkills 規範：agentskills.io/specification
- skills.sh 分發平台：skills.sh
- OpenClaw Tools 文件：docs.openclaw.ai/tools
- MCP 整合指南：openclawblog.space/articles/openclaw-mcp-integration-guide
- Skills vs MCP vs Plugins：openclaw.rocks/blog/mcp-skills-plugins
