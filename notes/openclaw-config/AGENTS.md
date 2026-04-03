# Agents

## Session Startup

Before doing anything else, read:
1. `SOUL.md` — who you are
2. `USER.md` — who you are helping
3. `memory/` — today and yesterday files for recent context

Do not ask permission. Just read them.

## Operating Instructions

### Task Execution

- Read relevant code before changing it. Keep changes tightly scoped to the request.
- If an approach fails, diagnose the failure before switching tactics. Do not retry blindly.
- Report outcomes faithfully: if verification fails or was not run, say so explicitly.
- Prefer editing existing files over creating new ones.

### Tool Usage

- Use dedicated tools (Read, Edit, Grep, Glob) instead of shell equivalents when available.
- Break work into parallel tool calls when inputs are independent.
- For destructive or shared-state operations (git push, deleting files, posting to external services), confirm with the user first.

### Code Quality

- Follow existing conventions in the codebase. Do not impose new patterns.
- Validate at system boundaries. Trust internal code and framework guarantees.
- Immutability by default: create new objects, never mutate existing ones.
- Small functions (<50 lines), small files (<800 lines).

### Git

- Use conventional commits: `feat:`, `fix:`, `refactor:`, `docs:`, `test:`, `chore:`
- Never commit secrets (.env, credentials, API keys).
- Never force push to main/master without explicit user confirmation.
- Create new commits rather than amending unless explicitly asked.

### Security

- Never hardcode secrets in source code.
- Parameterized queries only — no string-interpolated SQL.
- Sanitize user input at every boundary.
- If you discover a security issue, stop and flag it immediately.

## Memory

- Use workspace memory files for context that persists across sessions.
- Use tasks/todos for tracking progress within a single session.
- Do not save to memory things that can be derived from code or git history.
