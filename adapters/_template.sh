# shellcheck shell=bash
# Adapter template. Copy to adapters/<name>.sh (lowercase, no leading "_").
# dispatch.sh sources this file and calls exactly these two functions.

# Print version and exit 0 if the CLI is installed and usable; non-zero otherwise.
adapter_check() { command -v mycli >/dev/null && mycli --version; }

# adapter_run <workdir> <brief-file> <last-message-file> <model|""> <write|read-only>
# - Run ONE non-interactive turn with the brief as the prompt, cwd = <workdir>.
# - write: allow file edits inside <workdir> only. read-only ($mode): no edits.
# - Keep the harness sandbox ON; never pass "skip permissions"/"bypass" flags.
# - Write the agent's final message to <last-message-file>; stdout/stderr go to the log.
# - Return the CLI's exit code. dispatch.sh handles timeout, worktree and logs.
adapter_run() {
  local wd=$1 brief=$2 out=$3 model=$4 mode=$5
  local flag=--allow-edits; [[ $mode == read-only ]] && flag=--read-only
  ( cd "$wd" && mycli --prompt "$(cat "$brief")" "$flag" ${model:+--model "$model"} ) | tee "$out"
}

# --- optional live mode (tmux TUI), see references/live-mode.md ---
# adapter_live_cmd() { printf 'mycli --cwd %q' "$1"; }   # <workdir> <model> <mode>
# adapter_live_busy() { echo 'esc to interrupt'; }        # regex: worker busy
# adapter_live_ask() { echo 'Allow|\[y/n\]'; }            # regex: dialog waiting
