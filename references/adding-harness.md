# Adding a Harness

1. `cp adapters/_template.sh adapters/<name>.sh` (lowercase; names starting
   with `_` are ignored).
2. Implement `adapter_check` (exit 0 + print version when usable) and
   `adapter_run <workdir> <brief> <last-message-file> <model> <write|read-only>`.
3. Read the CLI's `--help` for its non-interactive mode, sandbox/permission
   mode, model flag, and how to capture the final message. Keep its sandbox on;
   never use skip-permission or bypass flags.
4. `dispatch.sh list` must show it as `available`.
5. Smoke test on a throwaway repo with a tiny brief (fix a function + test),
   then verify the diff and run the test yourself.
6. Optional live mode: add the `adapter_live_*` hooks (see
   [live-mode.md](live-mode.md)) and test `run --live` on the same repo.
7. Add a row to the "Choosing a Worker" table in SKILL.md.

Candidates: opencode, qwen-code, cursor-agent, aider (`--message`, `--yes` is
NOT allowed - it auto-approves everything).
