#!/usr/bin/env bash
# XOCHI setup launcher. Run this file in Terminal:
#   bash Xochi.sh
# macOS, Bash 3.2. Source state lives in ./var.
# The signed app keeps state in ~/Library/Application Support/XOCHI.
set -u
set -o pipefail

XO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" || exit 1
source "$XO_ROOT/Common.sh" || exit 1
source "$XO_ROOT/Tui.sh" || exit 1
source "$XO_ROOT/Recipes/Ollama.sh" || exit 1
source "$XO_ROOT/Recipes/Hermes.sh" || exit 1
source "$XO_ROOT/Recipes/OpenClaw.sh" || exit 1
source "$XO_ROOT/Recipes/Custom.sh" || exit 1

xo_cleanup() {
  if [[ -n "${XO_STTY:-}" ]]; then
    stty "$XO_STTY" 2>/dev/null || true
  fi
  if (( XO_SCREEN_ACTIVE )); then
    printf '\033[0m\033[?25h\033[?1049l'
  fi
  xo_release_lock
}

trap xo_cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP
trap 'XO_SIZE_STALE=1' WINCH

xo_dispatch() {
  local key="$1" status=0
  xo_prompt_screen
  case "$key" in
    H) xo_hermes_action || status=$? ;;
    O) xo_openclaw_action || status=$? ;;
    L) xo_ollama_action || status=$? ;;
    S) xo_custom_server_action || status=$? ;;
    A) xo_custom_agent_action || status=$? ;;
    *) XO_NOTICE="Unknown shortcut."; status=1 ;;
  esac
  if (( status != 0 )); then
    printf '\n%s%s%s\n' "$XO_RED" "$XO_NOTICE" "$XO_RESET"
    xo_pause
  fi
  xo_refresh force
  XO_FORCE_DRAW=1
}

[[ -t 0 && -t 1 ]] || xo_fatal "Run Xochi.sh in an interactive terminal."
[[ "$(uname -s)" == Darwin ]] || xo_fatal "This setup runs on macOS."

xo_ensure_utf8
xo_init
XO_STTY="$(stty -g)" || xo_fatal "Cannot read terminal settings."
XO_SIZE_STALE=1
XO_FORCE_DRAW=1

printf '\033[?1049h\033[2J\033[H\033[?25l'
XO_SCREEN_ACTIVE=1
xo_snapshot() {
  printf '%s|%s|%s|%s|%s|%s|%s|%s|%s' \
    "$XO_NOTICE" "$XO_SERVER" "$XO_OLLAMA_HEALTH" "$XO_CUSTOM_HEALTH_STATE" \
    "$XO_BIN_OLLAMA" "$XO_BIN_HERMES" "$XO_BIN_OPENCLAW" \
    "$XO_ROWS" "$XO_COLS"
}

xo_read_size
XO_SIZE_STALE=0
xo_refresh force
xo_draw
snapshot="$(xo_snapshot)"
XO_FORCE_DRAW=0

while true; do
  if (( XO_SIZE_STALE )); then
    xo_read_size
    XO_SIZE_STALE=0
    XO_FORCE_DRAW=1
  fi
  xo_refresh
  now="$(xo_snapshot)"
  if (( XO_FORCE_DRAW )) || [[ "$now" != "$snapshot" ]]; then
    xo_draw
    snapshot="$(xo_snapshot)"
    XO_FORCE_DRAW=0
  fi
  key=""
  if read -rsn1 -t 1 key; then
    case "$key" in
      h) key=H ;;
      o) key=O ;;
      l) key=L ;;
      s) key=S ;;
      a) key=A ;;
      q) key=Q ;;
    esac
    [[ "$key" == Q ]] && exit 0
    case "$key" in
      H|O|L|S|A) xo_dispatch "$key" ;;
    esac
  elif [[ ! -t 0 ]]; then
    # Timeout and end of input both return 1 on Bash 3.2.
    # A closed terminal is no longer a tty. A timeout still is.
    exit 0
  fi
done
