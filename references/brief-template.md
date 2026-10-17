# Worker Brief Template

Copy into `brief.md`, fill every field, delete hints in `<>`. The worker has
**no** access to the foreman's conversation: everything it needs is here.

```markdown
# Task: <short imperative title>

## Goal
<1-3 sentences: the observable outcome, not the implementation.>

## Context
- Repo: <what it is, stack, package manager>
- Relevant files: <path - why it matters>
- Conventions: <naming, style, test framework, patterns to copy from file X>

## Scope
- Allowed to change: <explicit list of files/dirs>
- Must NOT touch: <files, public APIs, configs, lockfiles>
- Out of scope: <tempting adjacent work to skip>

## Rules
- Do not git commit, push, rebase, or switch branches.
- Do not delete or weaken existing tests.
- Do not add dependencies unless listed here: <none>
- If blocked or a decision is needed, stop and explain in the final message.

## Done when
- `<exact verification command>` exits 0
- <behavioral check, e.g. "GET /users?page=2 returns 20 items">

## Final message format
1. Files changed (one line each, why)
2. Commands run and their actual output (last lines)
3. Anything unfinished, assumed, or risky
```

## Revision Brief (round 2+)

Same task id, new brief file. Keep it short and concrete:

```markdown
# Revision <n> for task <id>
The previous attempt is already in this worktree. Fix only the issues below.

## Issues found in review
1. <file:line> - <what is wrong> - <expected>
2. <failing command> output: <relevant lines>

## Keep
<what was correct and must not change>

## Done when
<same check as before, plus any new one>
```

## Foreman Review Checklist

Run these yourself; do not delegate.

- [ ] `git -C <wt> status --short` - only allowed files changed, no stray files
- [ ] `git -C <wt> diff` - read fully; logic matches goal
- [ ] No tests deleted or assertions weakened; no `skip`/`xit`/`@ts-ignore` added
- [ ] No secrets, debug prints, or commented-out blocks left
- [ ] Verification command run by you, inside the worktree, output captured
- [ ] UI change: viewed in the browser as the owner would use it
- [ ] `dispatch.sh status` shows no worker commits (or they were inspected)
