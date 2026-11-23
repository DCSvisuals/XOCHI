#!/usr/bin/env bash
# Ollama recipe. brew installs the command. XOCHI starts the server.
# Models stay in ~/.ollama. This does not open Ollama.app.

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  printf 'Run Xochi.sh instead.\n' >&2
  exit 1
fi

XO_OLLAMA_INSTALL="brew install ollama"

xo_ollama_action() {
  xo_refresh force
  if [[ -z "$XO_BIN_OLLAMA" ]]; then
    xo_require_tools brew || return 1
    printf 'Ollama is not installed.\n'
    printf 'brew installs the command. Models go to ~/.ollama.\n'
    printf 'XOCHI starts the server itself and does not open Ollama.app.\n'
    xo_run_shell "ollama-install" "$XO_OLLAMA_INSTALL" || return 1
    if [[ "$XO_NOTICE" == "Cancelled." ]]; then
      return 0
    fi
    xo_refresh force
    if [[ -z "$XO_BIN_OLLAMA" ]]; then
      XO_NOTICE="brew finished, but the ollama command was not found."
      return 1
    fi
  fi

  if [[ "$XO_OLLAMA_HEALTH" == up ]]; then
    XO_SERVER="ollama"
    if ! xo_save_settings; then
      XO_NOTICE="Ollama is ready, but that choice could not be saved."
      return 1
    fi
    XO_NOTICE="Ollama is ready. H and O will check it."
    return 0
  fi

  printf 'Start command:\nOLLAMA_HOST=127.0.0.1:11434 %s serve\n' "$XO_BIN_OLLAMA"
  printf 'Quit leaves this process running.\n'
  if ! xo_confirm "Start Ollama on 127.0.0.1:11434?"; then
    XO_NOTICE="Cancelled."
    return 0
  fi

  mkdir -p "$XO_LOG_DIR" || {
    XO_NOTICE="Could not create $(xo_rel "$XO_LOG_DIR")."
    return 1
  }
  nohup env OLLAMA_HOST="127.0.0.1:11434" "$XO_BIN_OLLAMA" serve \
    >> "$XO_LOG_DIR/ollama.log" 2>&1 < /dev/null &
  printf '%s\n' "$!" > "$XO_VAR/ollama.pid" || true
  xo_receipt "ollama-serve" \
    "OLLAMA_HOST=127.0.0.1:11434 $XO_BIN_OLLAMA serve" "0" || true

  if ! xo_wait_url "$XO_OLLAMA_URL/api/version" 20; then
    XO_NOTICE="Ollama did not respond. See $(xo_rel "$XO_LOG_DIR/ollama.log")."
    return 1
  fi
  XO_OLLAMA_HEALTH="up"
  XO_SERVER="ollama"
  if ! xo_save_settings; then
    XO_NOTICE="Ollama is ready, but that choice could not be saved."
    return 1
  fi
  XO_NOTICE="Ollama is ready. H and O will check it."
}
