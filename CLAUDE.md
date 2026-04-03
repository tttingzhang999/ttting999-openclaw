# CLAUDE.md — ting-openclaw

## 專案概述

這是個人 OpenClaw skills monorepo。OpenClaw 是開源自架 AI agent runtime，透過 Discord 與家人互動，作為記帳助手、日程助手、學習助手。

## 目錄約定

```
skills/<skill-name>/
├── SKILL.md              # 必要：skill 指引（Level 2）
├── SCHEMA.md / *.md      # 選用：參考文件（Level 3，按需讀取）
├── schema.sql / *.sql    # 選用：DB DDL（bundled，auto-init 用）
└── scripts/              # 選用：可執行腳本（Level 3，executed not loaded）
    └── *.sh

notes/
├── best-practices/       # OpenClaw 最佳實踐筆記
└── operations/           # 操作紀錄
```

每個 skill 是 self-contained unit：所有腳本、schema、參考文件都 bundle 在 skill 目錄內。
Symlink 部署時整個目錄帶走即可運作，不依賴 repo 其他位置。

## Skill 開發規範

### SKILL.md 格式（遵循 Claude Agent Skills 規範）

```markdown
---
name: skill-name
description: Third-person English description of what it does and when to trigger. ≤1024 chars.
---

# Skill 名稱

## 觸發條件
描述什麼時候觸發這個 skill。

## 指令
具體的步驟說明，讓 LLM 知道該怎麼做。

## 規則
限制與邊界條件。
```

### Progressive Disclosure（三層載入）

| Level | 載入時機 | Token 成本 | 內容 |
|-------|----------|-----------|------|
| 1 Metadata | 啟動時 | ~100 tokens | frontmatter `name` + `description` |
| 2 Instructions | 觸發時 | <5k tokens | SKILL.md body（保持 <500 行） |
| 3 Resources | 按需 | 無上限 | 參考文件（*.md）、腳本（scripts/）、SQL |

SKILL.md 超過 500 行時，將詳細內容拆到獨立檔案，用 `[SCHEMA.md](SCHEMA.md)` 引用。

### 撰寫原則

- 指令要具體明確，避免模糊描述（LLM 會照字面執行）
- 用 `{baseDir}` 引用 skill 目錄路徑
- 安全第一：使用 bash 的 skill 必須防止指令注入
- frontmatter 的 `metadata` 必須是單行 JSON（OpenClaw parser 限制）
- 家庭成員會使用，所以回應語言預設繁體中文
- description 要包含 **做什麼** + **什麼時候觸發**，第三人稱英文

### Skill 命名

- 目錄名用 kebab-case
- frontmatter `name` 用 kebab-case（符合 Claude Agent Skills 規範，≤64 chars）
- 不加 "family" 前綴，保持簡潔通用（如 `expense` 而非 `family-expense`）

### DB 整合模式（適用於需要持久化的 skill）

需要 DB 的 skill 採用以下模式：

1. **Database-per-service 隔離**：每個 skill 獨立 database（如 `expense`、`calendar`）
2. **Shell CLI wrapper**：`scripts/*.sh` 接受子命令 + 參數，內部做 parameterized SQL，LLM 不直接寫 SQL
3. **Auto-init**：CLI 首次執行時自動檢查 database 是否存在，不存在則建表 + seed
4. **JSON 輸出**：所有 CLI 輸出為 JSON，方便 LLM 解析
5. **安全措施**：嚴格驗證所有輸入（日期格式、enum 值、正整數），使用 `jq` 組裝 JSON 避免注入

```bash
# expense skill 為參考實作
skills/expense/scripts/expense.sh add --type expense --amount 30 --category "日用品" ...
```

## 開發流程

1. 在 `skills/` 下建立新目錄
2. 撰寫 `SKILL.md`（含 frontmatter + 指令）
3. 如需 DB：建立 `schema.sql` + `scripts/*.sh`（CLI wrapper with auto-init）
4. 測試 CLI：直接執行 `scripts/*.sh` 驗證
5. 測試 agent：`openclaw agent --message "測試指令"`
6. 確認行為正確後 commit

## 技術環境

- **LLM backend**: OpenAI GPT (model: `openai-codex/gpt-5.4`)
- **通訊介面**: Discord（未來加 LINE）
- **筆記平台**: Notion（skills 可能需要透過 Notion API 讀寫）
- **套件管理**: uv（不使用 python & pip）
- **資料庫**: 本機 PostgreSQL，每個服務獨立 database 隔離（如 `expense`、`calendar`）
- **目標使用者**: 家庭成員（非技術人員也會使用）

## 本機 OpenClaw 路徑與架構

### Runtime 目錄：`~/.openclaw/`

```
~/.openclaw/
├── openclaw.json              # 主設定檔（agents, bindings, channels, gateway）
├── CLAUDE.md                  # 全域 system prompt
├── agents/                    # Agent 實例狀態 & sessions
│   ├── main/
│   ├── finance/
│   └── japanese-vocabulary/
├── workspace/                 # main agent workspace
│   └── skills/discord/        # Discord 整合 (from clawhub)
├── workspace-finance/         # finance agent workspace
│   └── skills/expense/        # ← 從本 repo cp -r 部署
├── workspace-japanese-vocabulary/  # japanese-vocabulary agent workspace
│   └── skills/anki-learning/  # ← 從本 repo cp -r 部署
├── identity/                  # 裝置認證
├── memory/                    # 全域記憶 (SQLite)
├── cron/                      # 排程任務
├── logs/                      # 執行日誌
├── delivery-queue/            # 訊息佇列
├── devices/                   # 連線裝置
└── exec-approvals.json        # 工具執行授權紀錄
```

### Agent 架構

| Agent ID | Workspace | 綁定 Discord 頻道 | 部署的 Skills |
|----------|-----------|-------------------|---------------|
| `main` | `~/.openclaw/workspace/` | 所有未綁定的 Discord 訊息 | discord, apple-notes, notion, github, slack... (26 skills) |
| `finance` | `~/.openclaw/workspace-finance/` | `#1482769246361616404` | expense, coding-agent, github, model-usage, peekaboo |
| `japanese-vocabulary` | `~/.openclaw/workspace-japanese-vocabulary/` | `#1483707902324641822`, `#1483707939708473394` | anki-learning, discord, model-usage, peekaboo |

### Skill 部署對照（repo → 本機）

| Repo Skill | 部署目標 |
|------------|---------|
| `skills/expense/` | `~/.openclaw/workspace-finance/skills/expense/` |
| `skills/anki-learning/` | `~/.openclaw/workspace-japanese-vocabulary/skills/anki-learning/` |
| `skills/calendar/` | 尚未部署（WIP） |

### 部署指令

```bash
# expense skill → finance agent
cp -r skills/expense/ ~/.openclaw/workspace-finance/skills/expense/

# anki-learning skill → japanese-vocabulary agent
cp -r skills/anki-learning/ ~/.openclaw/workspace-japanese-vocabulary/skills/anki-learning/
```

## 注意事項

- OpenClaw 更新速度快，skill 格式可能變動，注意追蹤官方 changelog
- Skill 優先級：workspace > ~/.openclaw/skills > bundled，這個 repo 的 skills 放在 workspace 層級
- 第三方 skill 視為不信任代碼，啟用前先閱讀
- Symlink 無效（OpenClaw 做 realpath 安全檢查），必須 `cp -r` 直接複製
- Discord binding 在 `openclaw.json` 的 `bindings` 設定，依 channel ID 路由到對應 agent