#!/usr/bin/env bash
# XOCHI shared mechanics. Source this from Xochi.sh. Do not execute it.
# Bash 3.2. XOCHI state stays in $XO_ROOT/var. Other tools keep their own directories.

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  printf 'Run Xochi.sh instead.\n' >&2
  exit 1
fi

XO_VERSION="0.1"
XO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" || exit 1

# Source runs keep state beside the scripts. The signed app must not write
# inside itself, or the signature breaks on the first launch.
xo_choose_var() {
  local root="$1"
  case "$root" in
    *.app/Contents/*)
      printf '%s' "$HOME/Library/Application Support/XOCHI"
      ;;
    *)
      printf '%s' "$root/var"
      ;;
  esac
}

xo_rel() {
  local path="$1"
  case "$path" in
    "$HOME"/*) printf '~/%s' "${path#"$HOME"/}" ;;
    "$XO_ROOT"/*) printf '%s' "${path#"$XO_ROOT"/}" ;;
    *) printf '%s' "$path" ;;
  esac
}

XO_VAR="$(xo_choose_var "$XO_ROOT")"
XO_LOG_DIR="$XO_VAR/logs"
XO_RECEIPT_DIR="$XO_VAR/receipts"
XO_SETTINGS="$XO_VAR/settings"
XO_LOCK_DIR="$XO_VAR/dashboard.lock"
XO_OLLAMA_URL="http://127.0.0.1:11434"
XO_PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"

XO_NOTICE="First run. Commands run only after y."
XO_SERVER="ollama"
XO_CUSTOM_START=""
XO_CUSTOM_HEALTH=""
XO_AGENT_INSTALL=""
XO_AGENT_LAUNCH=""
XO_BIN_BREW=""
XO_BIN_GIT=""
XO_BIN_CURL=""
XO_BIN_OLLAMA=""
XO_BIN_HERMES=""
XO_BIN_OPENCLAW=""
XO_OLLAMA_HEALTH="down"
XO_CUSTOM_HEALTH_STATE="down"
XO_LOCK_HELD=0
XO_REFRESHED=-100
XO_STTY=""

XO_RESET=$'\033[0m'
XO_WHITE=$'\033[1;97m'
XO_GOLD=$'\033[1;38;5;179m'
XO_BORDER=$'\033[38;5;240m'
XO_MUTED=$'\033[38;5;245m'
XO_BODY=$'\033[38;5;252m'
XO_OK=$'\033[38;5;114m'
XO_WARN=$'\033[38;5;179m'
XO_BAD=$'\033[38;5;167m'
XO_RED=$'\033[1;91m'

xo_fatal() {
  printf 'XOCHI: %s\n' "$*" >&2
  exit 1
}

xo_confirm() {
  local answer=""
  printf '\n%s [y/N]: ' "$1"
  read -r answer || return 1
  [[ "$answer" == y || "$answer" == Y ]]
}

xo_pause() {
  printf '\nPress any key to return...'
  read -rsn1 || true
}

xo_valid_text() {
  local value="$1" max="$2"
  [[ -n "$value" ]] || return 1
  (( ${#value} <= max )) || return 1
  [[ "$value" != *[$'\n\r\033']* ]] || return 1
}

xo_valid_url() {
  local value="$1"
  xo_valid_text "$value" 200 || return 1
  [[ "$value" =~ ^https?://[^[:space:]]+$ ]]
}

xo_find_bin() {
  local name="$1" candidate
  candidate="$(command -v "$name" 2>/dev/null || true)"
  if [[ -n "$candidate" && -x "$candidate" && ! -d "$candidate" ]]; then
    printf '%s' "$candidate"
    return 0
  fi
  for candidate in \
    "$HOME/.local/bin/$name" \
    "/opt/homebrew/bin/$name" \
    "/usr/local/bin/$name"
  do
    if [[ -x "$candidate" && ! -d "$candidate" ]]; then
      printf '%s' "$candidate"
      return 0
    fi
  done
  return 1
}

xo_ensure_utf8() {
  case "${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" in
    *UTF-8*|*utf-8*) return 0 ;;
  esac
  if locale -a 2>/dev/null | grep -qi '^en_CA.UTF-8$'; then
    export LC_ALL=en_CA.UTF-8
  elif locale -a 2>/dev/null | grep -qi '^en_US.UTF-8$'; then
    export LC_ALL=en_US.UTF-8
  fi
}

xo_init() {
  umask 077
  mkdir -p "$XO_VAR" "$XO_LOG_DIR" "$XO_RECEIPT_DIR" ||
    xo_fatal "Cannot create $XO_VAR"
  chmod 700 "$XO_VAR" "$XO_LOG_DIR" "$XO_RECEIPT_DIR" ||
    xo_fatal "Cannot protect $XO_VAR"
  xo_acquire_lock || xo_fatal "$XO_NOTICE"
  xo_load_settings
  if [[ -f "$XO_SETTINGS" || -n "$(ls -A "$XO_RECEIPT_DIR" 2>/dev/null || true)" ]]; then
    XO_NOTICE="Ready."
  fi
}

xo_acquire_lock() {
  local owner=""
  if ! mkdir "$XO_LOCK_DIR" 2>/dev/null; then
    if [[ -f "$XO_LOCK_DIR/pid" ]]; then
      read -r owner < "$XO_LOCK_DIR/pid" || true
    fi
    if [[ "$owner" =~ ^[0-9]+$ ]] && kill -0 "$owner" 2>/dev/null; then
      XO_NOTICE="XOCHI is already running (pid ${owner})."
      return 1
    fi
    rm -rf "$XO_LOCK_DIR"
    mkdir "$XO_LOCK_DIR" || {
      XO_NOTICE="Cannot acquire the XOCHI lock."
      return 1
    }
  fi
  printf '%s\n' "$$" > "$XO_LOCK_DIR/pid" || return 1
  XO_LOCK_HELD=1
}

xo_release_lock() {
  local owner=""
  (( XO_LOCK_HELD )) || return 0
  if [[ -f "$XO_LOCK_DIR/pid" ]]; then
    read -r owner < "$XO_LOCK_DIR/pid" || true
  fi
  if [[ "$owner" == "$$" ]]; then
    rm -f "$XO_LOCK_DIR/pid"
    rmdir "$XO_LOCK_DIR" 2>/dev/null || true
  fi
  XO_LOCK_HELD=0
}

xo_load_settings() {
  local line key value
  [[ -f "$XO_SETTINGS" && ! -L "$XO_SETTINGS" ]] || return 0
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" == *=* ]] || continue
    key="${line%%=*}"
    value="${line#*=}"
    [[ "$value" != *[$'\n\r\033']* ]] || continue
    case "$key" in
      SERVER)
        [[ "$value" == ollama || "$value" == custom ]] && XO_SERVER="$value"
        ;;
      CUSTOM_START)
        xo_valid_text "$value" 500 && XO_CUSTOM_START="$value"
        ;;
      CUSTOM_HEALTH)
        xo_valid_url "$value" && XO_CUSTOM_HEALTH="$value"
        ;;
      AGENT_INSTALL)
        xo_valid_text "$value" 500 && XO_AGENT_INSTALL="$value"
        ;;
      AGENT_LAUNCH)
        xo_valid_text "$value" 500 && XO_AGENT_LAUNCH="$value"
        ;;
    esac
  done < "$XO_SETTINGS"
}

xo_save_settings() {
  local tmp
  [[ "$XO_SERVER" == ollama || "$XO_SERVER" == custom ]] || return 1
  tmp="$(mktemp "$XO_VAR/settings.XXXXXX")" || return 1
  if ! printf 'SERVER=%s\nCUSTOM_START=%s\nCUSTOM_HEALTH=%s\nAGENT_INSTALL=%s\nAGENT_LAUNCH=%s\n' \
    "$XO_SERVER" "$XO_CUSTOM_START" "$XO_CUSTOM_HEALTH" \
    "$XO_AGENT_INSTALL" "$XO_AGENT_LAUNCH" > "$tmp"; then
    rm -f "$tmp"
    return 1
  fi
  if ! mv -f "$tmp" "$XO_SETTINGS"; then
    rm -f "$tmp"
    return 1
  fi
  chmod 600 "$XO_SETTINGS" 2>/dev/null || true
}

xo_refresh() {
  local force="${1:-}"
  if [[ "$force" != force ]] && (( SECONDS - XO_REFRESHED < 3 )); then
    return 0
  fi
  hash -r 2>/dev/null || true
  XO_BIN_BREW="$(xo_find_bin brew || true)"
  XO_BIN_GIT="$(xo_find_bin git || true)"
  XO_BIN_CURL="$(xo_find_bin curl || true)"
  XO_BIN_OLLAMA="$(xo_find_bin ollama || true)"
  XO_BIN_HERMES="$(xo_find_bin hermes || true)"
  XO_BIN_OPENCLAW="$(xo_find_bin openclaw || true)"
  if curl -fsS --connect-timeout 0.4 --max-time 0.8 \
    -o /dev/null "$XO_OLLAMA_URL/api/version" 2>/dev/null; then
    XO_OLLAMA_HEALTH="up"
  else
    XO_OLLAMA_HEALTH="down"
  fi
  if [[ -n "$XO_CUSTOM_HEALTH" ]] &&
    curl -fsS --connect-timeout 0.4 --max-time 0.8 \
      -o /dev/null "$XO_CUSTOM_HEALTH" 2>/dev/null; then
    XO_CUSTOM_HEALTH_STATE="up"
  else
    XO_CUSTOM_HEALTH_STATE="down"
  fi
  XO_REFRESHED=$SECONDS
}

xo_server_ready() {
  xo_refresh force
  if [[ "$XO_SERVER" == custom ]]; then
    if [[ -z "$XO_CUSTOM_HEALTH" ]]; then
      XO_NOTICE="Custom server has no health URL. Press S."
      return 1
    fi
    if [[ "$XO_CUSTOM_HEALTH_STATE" != up ]]; then
      XO_NOTICE="Custom server is not responding. Press S."
      return 1
    fi
    return 0
  fi
  if [[ -z "$XO_BIN_OLLAMA" ]]; then
    XO_NOTICE="Ollama is not installed. Press L."
    return 1
  fi
  if [[ "$XO_OLLAMA_HEALTH" != up ]]; then
    XO_NOTICE="Ollama is not responding. Press L to start it."
    return 1
  fi
}

xo_model_is_27b() {
  local lower
  lower="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  [[ "$lower" =~ (^|[^0-9])(2[7-9]|[3-9][0-9]|[1-9][0-9]{2,})b([^a-z0-9]|$) ]]
}

xo_warn_27b() {
  local payload name hit=0
  [[ "$XO_SERVER" == ollama && "$XO_OLLAMA_HEALTH" == up ]] || return 0
  command -v python3 >/dev/null 2>&1 || return 0
  payload="$(curl -fsS --max-time 2 "$XO_OLLAMA_URL/api/tags" 2>/dev/null)" ||
    return 0
  while IFS= read -r name; do
    [[ -n "$name" ]] || continue
    if xo_model_is_27b "$name"; then
      hit=1
      break
    fi
  done < <(printf '%s' "$payload" | python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)
for item in data.get("models") or []:
    if isinstance(item, dict):
        name = item.get("name") or item.get("model") or ""
        if name:
            print(name)
')
  if (( hit )); then
    printf 'A 27B-class model is installed. Hermes needs at least 64000 tokens.\n'
    printf 'XOCHI does not change Hermes context, and it does not block smaller models.\n\n'
  fi
}

xo_require_tools() {
  local missing="" tool
  for tool in "$@"; do
    case "$tool" in
      brew) [[ -n "$XO_BIN_BREW" ]] || missing="${missing:+$missing, }brew" ;;
      git) [[ -n "$XO_BIN_GIT" ]] || missing="${missing:+$missing, }git" ;;
      curl) [[ -n "$XO_BIN_CURL" ]] || missing="${missing:+$missing, }curl" ;;
    esac
  done
  if [[ -n "$missing" ]]; then
    XO_NOTICE="Missing ${missing}. This recipe stops here."
    return 1
  fi
}

xo_receipt() {
  local label="$1" command="$2" code="$3" stamp receipt
  [[ "$label" =~ ^[a-z0-9-]+$ ]] || return 1
  mkdir -p "$XO_RECEIPT_DIR" || return 1
  stamp="$(date -u +%Y%m%dT%H%M%SZ)"
  receipt="$XO_RECEIPT_DIR/${label}-${stamp}.txt"
  printf 'time=%s\nexit=%s\nlog=%s\ncommand=%s\n' \
    "$stamp" "$code" "$XO_LOG_DIR/${label}.log" "$command" > "$receipt" || return 1
  chmod 600 "$receipt" 2>/dev/null || true
}

xo_run_shell() {
  local label="$1" command="$2" logfile code saved
  [[ "$label" =~ ^[a-z0-9-]+$ ]] || {
    XO_NOTICE="Internal command label rejected."
    return 1
  }
  xo_valid_text "$command" 500 || {
    XO_NOTICE="That command must be one non-empty line."
    return 1
  }
  printf '\nCommand:\n%s\n' "$command"
  if ! xo_confirm "Run this command?"; then
    XO_NOTICE="Cancelled."
    return 0
  fi
  mkdir -p "$XO_LOG_DIR" || {
    XO_NOTICE="Could not create $(xo_rel "$XO_LOG_DIR")."
    return 1
  }
  logfile="$XO_LOG_DIR/${label}.log"
  printf '\n--- %s ---\n%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$command" >> "$logfile"
  saved="$(stty -g 2>/dev/null || true)"
  env PATH="$XO_PATH" bash -c "$command" 2>&1 | tee -a "$logfile"
  code=${PIPESTATUS[0]}
  [[ -n "$saved" ]] && stty "$saved" 2>/dev/null || true
  xo_receipt "$label" "$command" "$code" || true
  printf '\nExit %s\n' "$code"
  if (( code != 0 )); then
    XO_NOTICE="Failed with exit ${code}. See $(xo_rel "$logfile")."
    return 1
  fi
  XO_NOTICE="Finished. See $(xo_rel "$logfile")."
  xo_refresh force
}

xo_wait_url() {
  local url="$1" tries="$2" i
  for ((i=0; i<tries; i++)); do
    if curl -fsS --connect-timeout 0.4 --max-time 0.8 -o /dev/null "$url" 2>/dev/null; then
      return 0
    fi
    sleep 0.5
  done
  return 1
}

xo_open_terminal() {
  local command="$1"
  xo_valid_text "$command" 500 || {
    XO_NOTICE="The launch command is not valid."
    return 1
  }
  if ! osascript - "$command" <<'APPLESCRIPT'
on run argv
  tell application "Terminal"
    do script (item 1 of argv)
    activate
  end tell
end run
APPLESCRIPT
  then
    XO_NOTICE="Terminal did not open the command."
    return 1
  fi
}

xo_prompt_screen() {
  [[ -n "$XO_STTY" ]] && stty "$XO_STTY" 2>/dev/null || true
  printf '\033[0m\033[?25h\033[2J\033[H'
}
