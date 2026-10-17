#!/usr/bin/env bash
# foreman dispatcher: run a task brief through an external harness CLI
# (codex, agy, ...) inside an isolated git worktree, with timeout and logs.
# Default is headless (exec/print). --live runs the harness TUI in a tmux
# session the user can watch (tmux attach -t <session>).
#
# Usage:
#   dispatch.sh list
#   dispatch.sh run <harness> <brief-file> --task <id> [--repo DIR] [--model M]
#                   [--timeout SEC] [--read-only] [--live] [--skip-permissions]
#     --skip-permissions: no per-command prompts (agy only); user opt-in only
#   dispatch.sh status <id> [--repo DIR]
#   dispatch.sh peek <id> [--repo DIR] [--lines N]     (live) show screen
#   dispatch.sh send <id> [--repo DIR] (--text "..." | --key KEY)  (live)
#   dispatch.sh wait <id> [--repo DIR] [--timeout SEC] (live) wait until idle
#   dispatch.sh clean <id> [--repo DIR] [--force]
#
# Exit codes: 0 ok, 2 usage, 3 harness unavailable, 4 timeout, 5 git/worktree
# error, 6 live worker waiting for input (read screen, answer via send),
# other = worker exit code.
set -uo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ADAPTER_DIR="$SKILL_DIR/adapters"
FOREMAN_HOME="${FOREMAN_HOME:-$HOME/.foreman}"

die() { local code=$1; shift; echo "foreman: $*" >&2; exit "$code"; }

load_adapter() {
  local name=$1 file="$ADAPTER_DIR/$1.sh"
  [[ "$name" =~ ^[a-z0-9_-]+$ && "$name" != _* && -f "$file" ]] \
    || die 3 "no adapter '$name' (see: dispatch.sh list)"
  # shellcheck source=/dev/null
  source "$file"
  adapter_check >/dev/null 2>&1 || die 3 "harness '$name' not installed or not working"
}

cmd_list() {
  local f name out
  for f in "$ADAPTER_DIR"/*.sh; do
    name=$(basename "$f" .sh)
    [[ "$name" == _* ]] && continue
    # shellcheck source=/dev/null
    if out=$( source "$f"; adapter_check 2>&1 ); then
      echo "$name	available	$(head -1 <<<"$out")"
    else
      echo "$name	missing"
    fi
  done
}

repo_root() { git -C "$1" rev-parse --show-toplevel 2>/dev/null || die 5 "not a git repo: $1"; }

paths_for() { # sets WT, BRANCH, RUN_DIR for task $1 in repo $2
  local slug; slug=$(basename "$2")
  WT="$FOREMAN_HOME/worktrees/$slug/$1"
  BRANCH="foreman/$1"
  RUN_DIR="$FOREMAN_HOME/runs/$slug/$1"
  SESS=$(printf 'fm-%s-%s' "$slug" "$1" | tr -c 'A-Za-z0-9_-' '-')
}

# ---- live mode (tmux) -------------------------------------------------------

screen() { tmux capture-pane -p -t "$SESS" -S "-${1:-60}" 2>/dev/null; }

# Poll the TUI screen. Returns 0 idle (busy marker gone, screen unchanged for
# 2 polls), 6 waiting for input (a dialog matching adapter_live_ask is shown),
# 4 timeout, 5 session exited.
live_wait() {
  local secs=$1 waited=0 stable=0 prev="" cur seen_busy=0
  while ((waited < secs)); do
    sleep 3; waited=$((waited + 3))
    tmux has-session -t "$SESS" 2>/dev/null || { echo "!! live session exited" >&2; return 5; }
    cur=$(screen 40)
    if [[ "$cur" == "$prev" ]]; then stable=$((stable + 1)); else stable=0; fi
    prev=$cur
    if ((stable >= 1)) && tail -12 <<<"$cur" | grep -Eq "$(adapter_live_ask)"; then return 6; fi
    if grep -Eq "$(adapter_live_busy)" <<<"$(tail -12 <<<"$cur")"; then seen_busy=1; continue; fi
    ((stable >= 2 && (seen_busy || waited >= 15))) && return 0
  done
  return 4
}

live_start() { # <workdir> <model> <mode>
  tmux has-session -t "$SESS" 2>/dev/null && return 0
  command -v tmux >/dev/null || die 3 "--live needs tmux (brew install tmux)"
  tmux new-session -d -s "$SESS" -x 200 -y 50 -c "$1" "$(adapter_live_cmd "$1" "$2" "$3")" \
    || die 3 "could not start tmux session $SESS"
  live_wait 60; local rc=$?
  # Policy: auto-accept a trust dialog only for a foreman-owned worktree.
  if [[ $rc -eq 6 ]] && declare -F adapter_live_trust_ok >/dev/null \
     && [[ "$1" == "$FOREMAN_HOME/worktrees/"* ]] \
     && screen 25 | grep -Fq "$1" && screen 25 | grep -Eq "$(adapter_live_trust_ok)"; then
    echo "foreman: auto-trusting foreman worktree $1" >&2
    tmux send-keys -t "$SESS" Enter
    live_wait 60; rc=$?
  fi
  [[ $rc -eq 6 ]] && { screen 25 | grep -v '^[[:space:]]*$'; rm -f "$PENDING_BRIEF"
    die 6 "worker asks for input at startup (e.g. trust prompt). Answer via dispatch.sh send, then rerun the same run command"; }
  return 0
}

live_paste() { # <file>
  tmux load-buffer -b foreman "$1" && tmux paste-buffer -p -d -b foreman -t "$SESS" \
    && sleep 1 && tmux send-keys -t "$SESS" Enter
}

live_task_ctx() { # <task> [--repo DIR] ... -> sets root/paths, loads adapter
  local repo="$PWD" task=$1; shift
  LIVE_ARGS=()
  while (($#)); do case $1 in --repo) repo=$2; shift 2 ;; *) LIVE_ARGS+=("$1"); shift ;; esac; done
  local root; root=$(repo_root "$repo"); paths_for "$task" "$root"
  [[ -f "$RUN_DIR/live-harness" ]] || die 2 "task '$task' has no live session"
  load_adapter "$(cat "$RUN_DIR/live-harness")"
  tmux has-session -t "$SESS" 2>/dev/null || die 5 "live session $SESS is not running"
}

cmd_peek() {
  live_task_ctx "$@"; local n=40
  [[ ${LIVE_ARGS[0]:-} == --lines ]] && n=${LIVE_ARGS[1]}
  screen "$n" | grep -v '^[[:space:]]*$' | tail -"$n"
}

cmd_send() {
  live_task_ctx "$@"
  case ${LIVE_ARGS[0]:-} in
    --text) tmux send-keys -t "$SESS" -l "${LIVE_ARGS[1]}" && sleep 0.5 && tmux send-keys -t "$SESS" Enter ;;
    --key) tmux send-keys -t "$SESS" "${LIVE_ARGS[1]}" ;;
    *) die 2 "send needs --text \"...\" or --key KEY" ;;
  esac
  echo "foreman: sent to $SESS; next: dispatch.sh wait <id>"
}

cmd_wait() {
  live_task_ctx "$@"; local secs=1800
  [[ ${LIVE_ARGS[0]:-} == --timeout ]] && secs=${LIVE_ARGS[1]}
  live_wait "$secs"; local rc=$?
  screen 300 > "$RUN_DIR/screen-latest.txt"
  screen 40 | grep -v '^[[:space:]]*$' | tail -30
  [[ $rc -eq 6 ]] && echo "!! worker is waiting for input (see screen above)"
  [[ $rc -eq 4 ]] && echo "!! still busy after ${secs}s"
  return "$rc"
}

# Run "$@" with a wall-clock limit (macOS has no coreutils `timeout`).
run_with_timeout() {
  local secs=$1; shift
  "$@" & local pid=$!
  ( sleep "$secs" && kill -TERM "$pid" 2>/dev/null && touch "$RUN_DIR/.timeout" ) &
  local watchdog=$!
  wait "$pid"; local rc=$?
  kill "$watchdog" 2>/dev/null; wait "$watchdog" 2>/dev/null
  [[ -f "$RUN_DIR/.timeout" ]] && { rm -f "$RUN_DIR/.timeout"; return 124; }
  return "$rc"
}

cmd_run() {
  local harness=${1:-} brief=${2:-}; shift 2 2>/dev/null || die 2 "run needs <harness> <brief-file>"
  local task="" repo="$PWD" model="" timeout=1800 mode=write live=0 skip=0
  while (($#)); do
    case $1 in
      --task) task=$2; shift 2 ;;
      --repo) repo=$2; shift 2 ;;
      --model) model=$2; shift 2 ;;
      --timeout) timeout=$2; shift 2 ;;
      --read-only) mode=read-only; shift ;;
      --live) live=1; shift ;;
      --skip-permissions) skip=1; shift ;;
      *) die 2 "unknown option: $1" ;;
    esac
  done
  [[ -n "$task" && "$task" =~ ^[a-z0-9][a-z0-9._-]*$ ]] || die 2 "--task <id> required (lowercase, a-z0-9._-)"
  [[ -f "$brief" ]] || die 2 "brief not found: $brief"
  load_adapter "$harness"
  if ((skip)); then
    declare -F adapter_supports_skip_permissions >/dev/null \
      || die 2 "harness '$harness' does not support --skip-permissions"
    export FOREMAN_SKIP_PERMISSIONS=1
    echo "!! foreman: $harness runs WITHOUT permission prompts (user opt-in); sandbox + worktree still on" >&2
  fi

  local root; root=$(repo_root "$repo")
  paths_for "$task" "$root"
  mkdir -p "$RUN_DIR"
  local round=1 f
  for f in "$RUN_DIR"/brief-*.md; do [[ -e "$f" ]] && round=$((round + 1)); done
  cp "$brief" "$RUN_DIR/brief-$round.md"

  local workdir="$root"
  if [[ $mode == write ]]; then
    if [[ ! -d "$WT" ]]; then
      mkdir -p "$(dirname "$WT")"
      git -C "$root" worktree add -q -b "$BRANCH" "$WT" HEAD 2>"$RUN_DIR/git.err" \
        || die 5 "worktree add failed: $(cat "$RUN_DIR/git.err")"
      git -C "$root" rev-parse HEAD > "$RUN_DIR/base"
    fi
    workdir="$WT"
  fi

  echo "foreman: $harness round $round -> $workdir (mode=$mode, timeout=${timeout}s, live=$live, skip_permissions=$skip)" >&2
  local start rc; start=$(date +%s)
  if ((live)); then
    declare -F adapter_live_cmd >/dev/null || die 3 "adapter '$harness' has no live support"
    echo "$harness" > "$RUN_DIR/live-harness"
    PENDING_BRIEF="$RUN_DIR/brief-$round.md" live_start "$workdir" "$model" "$mode"
    echo "foreman: watch with: tmux attach -t $SESS" >&2
    live_paste "$RUN_DIR/brief-$round.md" || die 5 "could not send brief to $SESS"
    live_wait "$timeout"; rc=$?
    [[ $rc -eq 4 ]] && rc=124
    screen 300 > "$RUN_DIR/log-$round.txt"
    screen 60 | grep -v '^[[:space:]]*$' | tail -40 > "$RUN_DIR/last-$round.md"
    [[ $rc -eq 6 ]] && echo "!! worker is waiting for input: read the screen, answer with dispatch.sh send, then dispatch.sh wait" >> "$RUN_DIR/last-$round.md"
  else
    run_with_timeout "$timeout" adapter_run "$workdir" "$RUN_DIR/brief-$round.md" \
      "$RUN_DIR/last-$round.md" "$model" "$mode" >"$RUN_DIR/log-$round.txt" 2>&1
    rc=$?
  fi
  local dur=$(( $(date +%s) - start ))
  printf '{"harness":"%s","task":"%s","round":%d,"mode":"%s","skip_permissions":%d,"exit":%d,"seconds":%d,"workdir":"%s"}\n' \
    "$harness" "$task" "$round" "$mode" "$skip" "$rc" "$dur" "$workdir" >> "$RUN_DIR/meta.jsonl"

  echo "== exit=$rc seconds=$dur log=$RUN_DIR/log-$round.txt"
  echo "== worker final message ($RUN_DIR/last-$round.md):"
  if [[ -s "$RUN_DIR/last-$round.md" ]]; then tail -40 "$RUN_DIR/last-$round.md"; else tail -20 "$RUN_DIR/log-$round.txt"; fi
  [[ $mode == write ]] && cmd_status "$task" --repo "$root"
  [[ $rc -eq 124 ]] && return 4
  return "$rc"
}

cmd_status() {
  local task=${1:-} repo="$PWD"; shift || true
  [[ ${1:-} == --repo ]] && repo=$2
  local root; root=$(repo_root "$repo"); paths_for "$task" "$root"
  [[ -d "$WT" ]] || die 5 "no worktree for task '$task'"
  local base; base=$(cat "$RUN_DIR/base" 2>/dev/null || git -C "$root" rev-parse HEAD)
  echo "== worktree $WT (branch $BRANCH, base ${base:0:10})"
  local ahead; ahead=$(git -C "$WT" rev-list --count "$base..HEAD")
  [[ $ahead -gt 0 ]] && echo "!! worker made $ahead commit(s) - briefs forbid commits; inspect before merge"
  git -C "$WT" status --short
  git -C "$WT" add -N . 2>/dev/null
  git -C "$WT" diff --stat "$base"
}

cmd_clean() {
  local task=${1:-} repo="$PWD" force=""; shift || true
  while (($#)); do case $1 in --repo) repo=$2; shift 2 ;; --force) force=--force; shift ;; *) shift ;; esac; done
  local root; root=$(repo_root "$repo"); paths_for "$task" "$root"
  tmux kill-session -t "$SESS" 2>/dev/null && echo "foreman: killed live session $SESS"
  if [[ ! -d "$WT" ]]; then rm -f "$RUN_DIR/live-harness"; echo "foreman: no worktree for '$task'"; return 0; fi
  git -C "$root" worktree remove $force "$WT" || die 5 "worktree has changes; rerun with --force to discard"
  if [[ -f "$RUN_DIR/live-harness" ]]; then
    load_adapter "$(cat "$RUN_DIR/live-harness")"
    declare -F adapter_live_untrust >/dev/null && adapter_live_untrust "$WT"
    rm -f "$RUN_DIR/live-harness"
  fi
  git -C "$root" branch -D "$BRANCH" >/dev/null 2>&1
  echo "foreman: removed $WT and $BRANCH (logs kept in $RUN_DIR)"
}

case ${1:-} in
  list) cmd_list ;;
  run) shift; cmd_run "$@" ;;
  status) shift; cmd_status "$@" ;;
  peek) shift; cmd_peek "$@" ;;
  send) shift; cmd_send "$@" ;;
  wait) shift; cmd_wait "$@" ;;
  clean) shift; cmd_clean "$@" ;;
  *) sed -n '2,21p' "$0"; exit 2 ;;
esac
