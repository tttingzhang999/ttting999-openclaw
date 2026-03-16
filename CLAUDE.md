# CLAUDE.md — ting-openclaw

## 專案概述

這是個人 OpenClaw skills monorepo。OpenClaw 是開源自架 AI agent runtime，透過 Discord 與家人互動，作為家庭日程助手、記帳助手、學習助手。

## 目錄約定

- `skills/<skill-name>/SKILL.md` — OpenClaw skills，每個 skill 一個目錄
- `notes/best-practices/` — OpenClaw 最佳實踐筆記
- `notes/operations/` — 操作紀錄

## Skill 開發規範

### SKILL.md 格式

```markdown
---
name: skill_name
description: 一句話描述 skill 功能
metadata: {"openclaw": {"requires": {"env": ["REQUIRED_ENV_VAR"]}, "primaryEnv": "MAIN_API_KEY"}}
---

# Skill 名稱

## 觸發條件
描述什麼時候觸發這個 skill。

## 指令
具體的步驟說明，讓 LLM 知道該怎麼做。

## 規則
限制與邊界條件。
```

### 撰寫原則

- 指令要具體明確，避免模糊描述（LLM 會照字面執行）
- 用 `{baseDir}` 引用 skill 目錄路徑
- 安全第一：使用 bash 的 skill 必須防止指令注入
- frontmatter 的 `metadata` 必須是單行 JSON
- 家庭成員會使用，所以回應語言預設繁體中文

### Skill 命名

- 目錄名用 kebab-case
- frontmatter `name` 用 snake_case
- 描述用英文（OpenClaw 慣例）

## 開發流程

1. 在 `skills/` 下建立新目錄
2. 撰寫 `SKILL.md`（含 frontmatter + 指令）
3. 測試：`openclaw agent --message "測試指令"`
4. 確認行為正確後 commit

## 技術環境

- **LLM backend**: OpenAI GPT
- **通訊介面**: Discord（未來加 LINE）
- **筆記平台**: Notion（skills 可能需要透過 Notion API 讀寫）
- **目標使用者**: 家庭成員（非技術人員也會使用）

## 注意事項

- OpenClaw 更新速度快，skill 格式可能變動，注意追蹤官方 changelog
- Skill 優先級：workspace > ~/.openclaw/skills > bundled，這個 repo 的 skills 放在 workspace 層級
- 第三方 skill 視為不信任代碼，啟用前先閱讀
