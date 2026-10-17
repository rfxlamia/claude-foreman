# shellcheck shell=bash
# Adapter: OpenAI Codex CLI (`codex exec`, non-interactive).
# Sandbox: workspace-write for edits, read-only for review/research.
# Never use --dangerously-bypass-approvals-and-sandbox (--full-auto is removed).

adapter_check() { command -v codex >/dev/null && codex --version; }

# adapter_run <workdir> <brief-file> <last-message-file> <model|""> <write|read-only>
adapter_run() {
  local wd=$1 brief=$2 out=$3 model=$4 mode=$5 sandbox=workspace-write
  [[ $mode == read-only ]] && sandbox=read-only
  codex exec -C "$wd" -s "$sandbox" --skip-git-repo-check --color never \
    ${model:+-m "$model"} -o "$out" - < "$brief"
}

# --- live mode (tmux TUI) ---
adapter_live_cmd() { # <workdir> <model> <write|read-only>
  local sandbox=workspace-write; [[ $3 == read-only ]] && sandbox=read-only
  printf 'codex -C %q -s %s -a on-request --no-alt-screen' "$1" "$sandbox"
  [[ -n $2 ]] && printf ' -m %q' "$2"
}
adapter_live_busy() { echo 'esc to interrupt'; }
adapter_live_ask() { echo 'Would you like to|Press enter to confirm|Do you trust|\[y/n\]'; }
