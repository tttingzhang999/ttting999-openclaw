# ting-openclaw

個人 OpenClaw AI 助手設定 monorepo。包含自訂 skills、最佳實踐筆記、操作紀錄。

## 技術棧

- **Runtime**: [OpenClaw](https://github.com/openclaw/openclaw) (self-hosted)
- **LLM**: OpenAI GPT (`openai-codex/gpt-5.4`)
- **通訊介面**: Discord（預計新增 LINE）
- **筆記平台**: Notion
- **資料庫**: 本機 PostgreSQL（每個 skill 獨立 database 隔離）
- **套件管理**: uv（不使用 python & pip）
- **用途**: 記帳助手 / 工時追蹤 / 學習助手 / 工作日誌

## 目錄結構

```
ting-openclaw/
├── skills/                         # OpenClaw 自訂 skills（self-contained）
│   ├── anki-learning/              # Anki 式單字學習
│   ├── calendar/                   # 日程管理（WIP）
│   ├── expense/                    # 記帳
│   │   ├── SKILL.md                # Skill 指引
│   │   ├── SCHEMA.md               # DB schema 文件
│   │   ├── schema.sql              # DB DDL + seed
│   │   └── scripts/expense.sh      # CLI wrapper（auto-init DB）
│   ├── timetrack/                  # 三層工時追蹤
│   └── worklog/                    # 工作日誌 / 待辦追蹤
└── notes/                          # 筆記區
    ├── best-practices/             # OpenClaw 最佳實踐
    ├── daily/                      # 每日紀錄
    ├── openclaw-config/            # OpenClaw 人格與設定指南
    └── operations/                 # 操作紀錄
```

每個 skill 是 self-contained unit：SKILL.md、腳本、schema 全部 bundle 在同一目錄。
部署必須用 `cp -r`（symlink 無效，OpenClaw 做 realpath 安全檢查）。

## 快速開始

1. Clone

```bash
git clone <repo-url> ~/ting-openclaw
```

2. 部署 skill 到對應 agent workspace

```bash
# expense → finance agent
cp -r skills/expense/ ~/.openclaw/workspace-finance/skills/expense/

# anki-learning → japanese-vocabulary agent
cp -r skills/anki-learning/ ~/.openclaw/workspace-japanese-vocabulary/skills/anki-learning/
```

3. 測試（expense skill 首次執行會自動建表）

```bash
# CLI 直接測試
skills/expense/scripts/expense.sh categories

# 透過 agent 測試
openclaw agent --message "我剛買了立可帶, 30塊"
```

## Skills

| Skill | 狀態 | DB | 部署 Agent | 說明 |
|-------|------|-----|-----------|------|
| `expense` | ✅ 完成 | `expense` | `finance` | 收支記錄、分類、月報。Shell CLI wrapper + PostgreSQL |
| `anki-learning` | ✅ 完成 | `anki_learning` | `japanese-vocabulary` | Anki 式單字閃卡學習，追蹤進度，不重複出題 |
| `timetrack` | ✅ 完成 | `timetrack` | 尚未部署 | 三層工時追蹤（實際/內部/客戶），支援批次更新與報表 |
| `worklog` | 🔄 開發中 | `worklog` | 尚未部署 | 工作項目 / 待辦追蹤，自然語言輸入 |
| `calendar` | 🔄 開發中 | — | — | 家庭行事曆、提醒、排程 |

## Agent 架構

| Agent ID | Workspace | 綁定 Discord 頻道 | 部署的 Skills |
|----------|-----------|-------------------|---------------|
| `main` | `~/.openclaw/workspace/` | 所有未綁定的訊息 | discord, notion, github, slack... |
| `finance` | `~/.openclaw/workspace-finance/` | #記帳 | expense |
| `japanese-vocabulary` | `~/.openclaw/workspace-japanese-vocabulary/` | #日文學習 | anki-learning |

## 筆記區

- `notes/best-practices/` — OpenClaw 最佳實踐（驗證過的做法）
- `notes/daily/` — 每日紀錄
- `notes/openclaw-config/` — OpenClaw 人格設定與 agent 配置指南
- `notes/operations/` — 個人操作紀錄與踩坑筆記
