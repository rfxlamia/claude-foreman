# Live Mode (tmux)

Opt-in alternative to headless runs: the worker's interactive TUI runs in a
tmux session that both the foreman and the user can see and type into.

## When to use

| Use live | Stay headless (default) |
|---|---|
| User wants to watch the worker | Unattended or background work |
| Long back-and-forth with one worker context | One-shot tasks with a clear "done when" |
| Worker needs headless-denied tools (agy shell commands) | Parallel batches |

Requires `tmux` (`brew install tmux`).

## Flow

```bash
D=~/.claude/skills/foreman/scripts/dispatch.sh
$D run agy "$BRIEF" --task fix-x --live      # starts fm-<repo>-fix-x, pastes brief, waits
# Claude desktop: show it to the user
#   run_in_terminal: tmux attach -t fm-<repo>-fix-x
$D peek fix-x                                # current screen (last 40 lines)
$D send fix-x --text "Also cover negatives"  # follow-up in the same context
$D wait fix-x --timeout 600                  # until idle (0), dialog (6), timeout (4)
$D clean fix-x                               # kill session, remove worktree, untrust
```

Round 2+ with `run ... --live` on the same task pastes the new brief into the
existing session, so the worker keeps its context. Kill the session (clean,
or `tmux kill-session -t <session>`) to force a fresh context.

## How "done" is detected

`live_wait` polls the screen every 3 s:
- busy marker present (`adapter_live_busy`, e.g. codex `esc to interrupt`,
  agy `Generating|esc to cancel`) -> keep waiting;
- screen unchanged and a dialog marker in the last lines
  (`adapter_live_ask`) -> exit 6;
- screen unchanged for 2 polls after the worker was busy -> idle, exit 0.
Screen text is a heuristic: always confirm with `git diff` and your own checks.

## Exit 6: dialogs

Read the screen (`peek`), then:
- Read files / run the brief's verification or build command inside the
  worktree -> foreman may allow **once** (`send --key Enter` or the key the
  dialog shows), then `wait`.
- Anything else (install, network, delete, commit/push, outside worktree,
  "always allow", unknown) -> ask the user; they can answer in the tmux tab.
- Trust dialog: auto-accepted by dispatch.sh only for
  `~/.foreman/worktrees/...`; the entry is removed again on `clean` (agy).

## Adapter hooks for live support

`adapter_live_cmd <workdir> <model> <mode>` prints the TUI command line;
`adapter_live_busy` / `adapter_live_ask` print extended regexes;
optional `adapter_live_trust_ok` (regex proving "Yes" is selected) and
`adapter_live_untrust <path>` (undo the trust entry).
