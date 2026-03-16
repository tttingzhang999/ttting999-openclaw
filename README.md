# ting-openclaw

個人 OpenClaw AI 助手設定 monorepo。包含自訂 skills、最佳實踐筆記、操作紀錄。

## 技術棧

- **Runtime**: [OpenClaw](https://github.com/openclaw/openclaw) (self-hosted)
- **LLM**: OpenAI GPT
- **通訊介面**: Discord (預計新增 LINE)
- **筆記平台**: Notion
- **用途**: 家庭日程助手 / 記帳助手 / 學習助手

## 目錄結構

```
ting-openclaw/
├── skills/                    # OpenClaw 自訂 skills
│   ├── calendar/              # 日程管理
│   ├── expense/               # 記帳
│   └── study/                 # 學習助手
└── notes/                     # 筆記區
    ├── best-practices/        # OpenClaw 最佳實踐
    └── operations/            # 操作紀錄
```

## 快速開始

1. Clone 這個 repo

```bash
git clone <repo-url> ~/ting-openclaw
```

2. 將 skills 連結到 OpenClaw workspace

```bash
# 方法一：直接作為 workspace skills
ln -s ~/ting-openclaw/skills ~/.openclaw/workspace/skills

# 方法二：在 openclaw.json 中設定 extraDirs
# 在 ~/.openclaw/openclaw.json 加入：
# { "skills": { "load": { "extraDirs": ["~/ting-openclaw/skills"] } } }
```

3. 重啟 OpenClaw gateway 或請 agent "refresh skills"

## Skills

| Skill | 狀態 | 說明 |
|-------|------|------|
| `calendar` | WIP | 家庭行事曆、提醒、排程 |
| `expense` | WIP | 收支記錄、分類、月報 |
| `study` | WIP | 筆記整理、複習提醒、知識管理 |

## 筆記區

- `notes/best-practices/` — OpenClaw 最佳實踐（教學品質差異大，這裡整理驗證過的做法）
- `notes/operations/` — 個人操作紀錄與踩坑筆記
