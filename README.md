# ting-openclaw

個人 OpenClaw AI 助手設定 monorepo。包含自訂 skills、最佳實踐筆記、操作紀錄。

## 技術棧

- **Runtime**: [OpenClaw](https://github.com/openclaw/openclaw) (self-hosted)
- **LLM**: OpenAI GPT
- **通訊介面**: Discord (預計新增 LINE)
- **筆記平台**: Notion
- **資料庫**: 本機 PostgreSQL（每個 skill 獨立 database 隔離）
- **套件管理**: uv（不使用 python & pip）
- **用途**: 記帳助手 / 日程助手 / 學習助手

## 目錄結構

```
ting-openclaw/
├── skills/                         # OpenClaw 自訂 skills（self-contained）
│   ├── calendar/                   # 日程管理
│   ├── expense/                    # 記帳
│   │   ├── SKILL.md                # Skill 指引
│   │   ├── SCHEMA.md               # DB schema 文件
│   │   ├── schema.sql              # DB DDL + seed
│   │   └── scripts/expense.sh      # CLI wrapper（auto-init DB）
│   └── study/                      # 學習助手
└── notes/                          # 筆記區
    ├── best-practices/             # OpenClaw 最佳實踐
    └── operations/                 # 操作紀錄
```

每個 skill 是 self-contained unit：SKILL.md、腳本、schema 全部 bundle 在同一目錄。
Symlink 部署時整個目錄帶走即可運作。

## 快速開始

1. Clone

```bash
git clone <repo-url> ~/ting-openclaw
```

2. 建立 agent 並 symlink skills

```bash
openclaw agents add --id finance --workspace ~/.openclaw/workspace-finance
ln -s ~/ting-openclaw/skills/expense ~/.openclaw/workspace-finance/skills/expense
```

3. 測試（expense skill 首次執行會自動建表）

```bash
# CLI 直接測試
skills/expense/scripts/expense.sh categories

# 透過 agent 測試
openclaw agent --message "我剛買了立可帶, 30塊"
```

## Skills

| Skill | 狀態 | 說明 |
|-------|------|------|
| `expense` | ✅ Done | 收支記錄、分類、月報。Shell CLI wrapper + PostgreSQL，auto-init DB |
| `calendar` | WIP | 家庭行事曆、提醒、排程 |
| `study` | WIP | 筆記整理、複習提醒、知識管理 |

### Expense Skill

記帳功能，家人在 Discord #記帳 channel 透過自然語言或圖片+文字記錄收支。

- 支援支出 + 收入，11 個預設分類（可動態新增）
- 透過 Discord user ID 隔離不同用戶紀錄
- 金額 >= 1000 或 OCR 提取時需確認，其餘直接寫入
- CLI wrapper 做 input validation + SQL injection 防護，LLM 不直接碰 SQL

## 筆記區

- `notes/best-practices/` — OpenClaw 最佳實踐（驗證過的做法）
- `notes/operations/` — 個人操作紀錄與踩坑筆記
