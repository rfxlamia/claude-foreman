# Foreman

![Foreman project header](assets/foreman-header-transparent.png)

Foreman lets Claude delegate implementation work to external coding-agent CLIs. Claude acts as the foreman: it plans the work, writes a self-contained brief, reviews the diff, and verifies the result. A worker CLI does the implementation.

## Quick start

Install Foreman as a Claude Code plugin:

```bash
claude plugin marketplace add rfxlamia/claude-foreman
claude plugin install foreman@claude-foreman
```

Or with the skills CLI:

```bash
npx skills add rfxlamia/claude-foreman
```

Then run in claude :
```
/foreman
```

Fill in the brief before dispatching. It should state the goal, relevant context, allowed file scope, rules, and an exact verification command. The worker does not have access to the foreman's conversation. After the run, inspect the diff and run the checks yourself; a worker's report is not verification.

## How it works

By default, Foreman runs workers headlessly. Write-mode tasks run in an isolated Git worktree on a separate `foreman/<task>` branch, with the selected adapter's sandbox enabled. Read-only tasks run in the repository without edits. Workers should not commit, push, or modify the user's branch. The foreman reviews and verifies the changes before they are integrated.

The included adapters support OpenAI Codex (`codex exec`) and Google Antigravity (`agy -p`). Foreman can also support other coding-agent CLIs through adapters; see [Adding a harness](references/adding-harness.md) for the adapter contract and checklist.

Sandbox and permission behavior depends on the adapter. Codex runs with its sandbox on. Antigravity also keeps its sandbox on; it blocks writes outside the worktree and Git, but does not block network access. In headless mode, Antigravity shell commands are auto-denied unless the user has explicitly opted into `--skip-permissions`. Keep briefs scoped to the task and review worker changes before integration.

## Optional live mode

Use `--live` when you want to watch or co-drive a worker in its terminal UI. This mode uses a shared `tmux` session; the task still uses its worktree and adapter sandbox. Headless mode remains the default. Live mode requires `tmux`.

```bash
/foreman live mode
```

See [Live mode](references/live-mode.md) for sending follow-up instructions, handling permission dialogs, and cleaning up a session.

To add a harness, copy `adapters/_template.sh`, implement its availability check and run function while keeping the CLI sandbox enabled, then verify it on a throwaway repository. Live mode hooks are optional. See [Adding a harness](references/adding-harness.md) for the full checklist.
