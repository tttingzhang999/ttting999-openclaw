# OpenClaw Agent Config Guideline

Reusable configuration templates for OpenClaw agents. Designed to reduce verbosity and improve action-oriented behavior, inspired by Claude Code's system prompt patterns.

## Files

| File | Purpose | Customization needed |
|------|---------|---------------------|
| `SOUL.md` | Personality, communication rules, anti-verbosity | Opening role line; "What NOT to Do" section |
| `IDENTITY.md` | Name, creature, vibe | All fields (per agent) |
| `AGENTS.md` | Operating instructions, memory, group chat, heartbeats | Coding rules (add for dev agents); heartbeat checklist |
| `USER.md` | User profile, preferences, pet peeves | All fields (per deployment) |
| `gateway-agent.json5` | **Reference only** — gateway-level verbosity flags | Model name; review flag support in your runtime |

## How to Deploy to a New Agent

1. Copy workspace files to the agent's workspace:
   ```bash
   cp SOUL.md AGENTS.md USER.md IDENTITY.md ~/.openclaw/workspace-<agent>/
   ```

2. Customize `<!-- CUSTOMIZE -->` sections in each file:
   - `SOUL.md` — adjust the role description for the agent's domain
   - `USER.md` — fill in user info and relevant context
   - `IDENTITY.md` — give the agent a name and personality
   - `AGENTS.md` — add domain-specific rules (e.g., coding rules for dev agents)

3. Optionally create `HEARTBEAT.md` with a task checklist for proactive behavior.

4. For coding-focused agents, add these sections to `AGENTS.md`:
   ```markdown
   ### Code Quality
   - Follow existing conventions. Do not impose new patterns.
   - Immutability by default. Small functions (<50 lines), small files (<800 lines).

   ### Git
   - Conventional commits: feat:, fix:, refactor:, docs:, test:, chore:
   - Never commit secrets. Never force push to main without confirmation.

   ### Security
   - Parameterized queries only. Sanitize user input at every boundary.
   ```

## What This Solves

Default OpenClaw agents tend to be verbose — long preambles, unnecessary summaries, restating the question before answering. This guideline addresses that through:

1. **SOUL.md** — explicit "do not" rules against common verbosity patterns
2. **USER.md** — declares pet peeves so the agent has concrete anti-patterns to avoid
3. **AGENTS.md** — task execution rules: act first, explain only when asked
4. **gateway-agent.json5** — runtime flags (if supported): `verboseDefault: off`

## Design Rationale

Key principles borrowed from Claude Code's system prompt:
- "Lead with the answer or action, not the reasoning"
- "Do not restate what the user said"
- "Keep changes tightly scoped to the request"
- "Report outcomes faithfully"

Reference: [claw-code-parity](https://github.com/ultraworkers/claw-code-parity) — clean-room analysis of Claude Code's architecture.
