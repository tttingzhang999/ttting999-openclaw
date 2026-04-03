# OpenClaw Concise Agent Configuration

Configuration files for OpenClaw that replicate Claude Code's concise, action-oriented interaction style.

## Files

| File | Purpose | Where to place |
|------|---------|----------------|
| `SOUL.md` | Agent personality and communication rules | `~/.openclaw/workspace/SOUL.md` |
| `IDENTITY.md` | Name, creature, vibe | `~/.openclaw/workspace/IDENTITY.md` |
| `AGENTS.md` | Operating instructions, tool usage, git/security rules | `~/.openclaw/workspace/AGENTS.md` |
| `USER.md` | User preferences and pet peeves | `~/.openclaw/workspace/USER.md` |
| `gateway-agent.json5` | Gateway config with verboseDefault off | Merge into `openclaw.config.json5` |

## Quick Setup

```bash
# Copy workspace files
cp SOUL.md IDENTITY.md AGENTS.md USER.md ~/.openclaw/workspace/

# Apply identity
openclaw agents set-identity --workspace ~/.openclaw/workspace --from-identity

# Merge gateway config into your existing openclaw.config.json5
# (manually merge the agents section from gateway-agent.json5)
```

## What This Solves

The default OpenClaw agent tends to be verbose — long preambles, unnecessary summaries,
restating the question before answering. This configuration addresses that by:

1. **SOUL.md** — explicit "do not" rules against common verbosity patterns
2. **Gateway config** — `verboseDefault: "off"`, `reasoningDefault: "off"`, `fastModeDefault: true`
3. **USER.md** — declares user preferences so the agent has no excuse to over-explain
4. **AGENTS.md** — task execution rules modeled after Claude Code's system prompt

## Design Rationale

These files are reverse-engineered from the system prompt patterns in
`rust/crates/runtime/src/prompt.rs` of the claw-code-parity project.
Key insights borrowed from Claude Code:

- "Lead with the answer or action, not the reasoning"
- "Do not restate what the user said"
- "Keep changes tightly scoped to the request"
- "Report outcomes faithfully"
