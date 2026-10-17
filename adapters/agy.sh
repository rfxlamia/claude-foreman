# shellcheck shell=bash
# Adapter: Google Antigravity CLI (`agy -p`, Gemini models by default).
# Modes: accept-edits for edits, plan for review/research. Always --sandbox.
# Models: `agy models`.
# Without --skip-permissions, headless agy auto-denies shell commands (and
# still exits 0, so we flag it below) and live agy shows a dialog per command.
# --skip-permissions (dispatch.sh, user opt-in only) adds
# --dangerously-skip-permissions. --sandbox stays on: it blocks writes outside
# the workdir and git, but NOT network access.

adapter_check() { command -v agy >/dev/null && agy --version; }
adapter_supports_skip_permissions() { return 0; }
skip_flag() { [[ ${FOREMAN_SKIP_PERMISSIONS:-0} == 1 ]] && printf '%s' --dangerously-skip-permissions; }

# adapter_run <workdir> <brief-file> <last-message-file> <model|""> <write|read-only>
adapter_run() {
  local wd=$1 brief=$2 out=$3 model=$4 mode=$5 agy_mode=accept-edits
  [[ $mode == read-only ]] && agy_mode=plan
  # shellcheck disable=SC2046
  ( cd "$wd" && agy $(skip_flag) -p "$(cat "$brief")" --mode "$agy_mode" --sandbox \
      --print-timeout 0s ${model:+--model "$model"} ) | tee "$out"
  local rc=${PIPESTATUS[0]}
  if grep -qi 'auto-denied' "$out"; then
    echo "!! FOREMAN: agy was denied a tool permission; its self-reported checks did NOT run. Verify yourself." | tee -a "$out"
  fi
  return "$rc"
}

# --- live mode (tmux TUI); permission dialogs appear on screen ---
adapter_live_cmd() { # <workdir> <model> <write|read-only>
  local m=accept-edits; [[ $3 == read-only ]] && m=plan
  printf 'agy --mode %s --sandbox' "$m"
  [[ ${FOREMAN_SKIP_PERMISSIONS:-0} == 1 ]] && printf ' %s' "$(skip_flag)"
  [[ -n $2 ]] && printf ' --model %q' "$2"
}
adapter_live_busy() { echo 'Generating|esc to cancel'; }
# Command dialog reads "Requesting permission for: ... Run this command?" and
# its footer also shows "esc to cancel"; live_wait checks ask before busy.
adapter_live_ask() { echo 'Requesting permission|Run this command\?|enter Confirm|Do you trust|\(y/n\)'; }
# Trust dialog for a new folder: accept only when "Yes" is the selected option
# (dispatch.sh also requires the folder to be a foreman worktree).
adapter_live_trust_ok() { echo '> Yes, I trust this folder'; }
# Remove the folder from agy's trustedWorkspaces when the worktree is cleaned.
adapter_live_untrust() {
  local cfg="$HOME/.gemini/antigravity-cli/settings.json"
  [[ -f "$cfg" ]] || return 0
  python3 - "$cfg" "$1" <<'PY'
import json, sys
cfg, path = sys.argv[1], sys.argv[2]
data = json.load(open(cfg))
ws = data.get("trustedWorkspaces", [])
if path in ws:
    data["trustedWorkspaces"] = [w for w in ws if w != path]
    json.dump(data, open(cfg, "w"), indent=2)
    print(f"foreman: removed {path} from agy trustedWorkspaces")
PY
}
