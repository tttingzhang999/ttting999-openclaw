# OpenClaw Skill vs Claude Code Skill

## 完全不同的系統

| | OpenClaw Skill | Claude Code Skill |
|---|---|---|
| 格式 | `SKILL.md`（YAML frontmatter + Markdown） | Claude Code slash command |
| 執行者 | OpenClaw agent（OpenAI GPT 等 LLM） | Claude Code（Anthropic Claude） |
| 位置 | `~/.openclaw/workspace/skills/` | `~/.claude/commands/` |
| 用途 | 教 OpenClaw 完成使用者任務 | 教 Claude Code 執行開發操作 |
| 載入方式 | 自動掃描 skill 目錄 | slash command 觸發 |
| 註冊中心 | ClawHub（clawhub.com） | 無（本地或內建） |

## 在這個 Repo 中

- `skills/` — 給 OpenClaw 用的 skill（SKILL.md 格式）
- `CLAUDE.md` — 給 Claude Code 用的專案指引（不是 skill）
- `~/.claude/commands/` — Claude Code 的 custom slash commands（不在這個 repo）

## 共通點

兩者都是用 Markdown 描述指令讓 LLM 執行，概念相似但生態系統完全獨立。
