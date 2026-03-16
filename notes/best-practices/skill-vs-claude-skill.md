# OpenClaw Skill vs Claude Code Skill

## 格式相似，生態系統不同

兩者都遵循 AgentSkills 開放標準（`SKILL.md` + YAML frontmatter + Markdown），但運行在不同的 agent runtime 上。

| | OpenClaw Skill | Claude Code Skill |
|---|---|---|
| 格式 | `SKILL.md`（YAML frontmatter + Markdown） | `SKILL.md`（YAML frontmatter + Markdown） |
| 執行者 | OpenClaw agent（支援 OpenAI GPT、Claude、Gemini 等 LLM） | Claude Code（Anthropic Claude） |
| 位置 | `<workspace>/skills/` 或 `~/.openclaw/skills/` | `~/.claude/skills/` 或 `.claude/skills/` |
| 用途 | 教 OpenClaw 完成使用者任務 | 教 Claude Code 執行開發操作 |
| 載入方式 | 自動掃描 skill 目錄 | slash command 觸發 |
| 註冊中心 | ClawHub（clawhub.com） | 無（本地或內建） |
| 共用標準 | AgentSkills（agentskills.io） | AgentSkills（agentskills.io） |

## 在這個 Repo 中

- `skills/` — 給 OpenClaw 用的 skill（SKILL.md 格式）
- `CLAUDE.md` — 給 Claude Code 用的專案指引（不是 skill）
- `~/.claude/skills/` — Claude Code 的 custom skills（不在這個 repo）

## 共通點

兩者都遵循 AgentSkills 開放規範，用 SKILL.md 描述指令讓 LLM 執行。在 OpenClaw 寫的 skill 不需修改就能發布到 skills.sh，供 Claude Code、Cursor 等平台使用。
