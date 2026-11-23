#!/usr/bin/env bash
# Custom server and custom agent. The user supplies the commands.
# XOCHI does not invent flags for LM Studio, llama.cpp, MLX, or unknown agents.

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  printf 'Run Xochi.sh instead.\n' >&2
  exit 1
fi

xo_custom_server_action() {
  local start="" health="" new_start="" new_health="" pid=""

  printf 'Custom server\n\n'
  printf 'Start:  %s\n' "${XO_CUSTOM_START:-unset}"
  printf 'Health: %s\n' "${XO_CUSTOM_HEALTH:-unset}"
  printf 'Saving both makes this the server H and O check.\n'
  printf 'L switches that check back to Ollama.\n'
  printf '\nStart command (Enter keeps current): '
  read -r start || return 0
  printf 'Health URL (Enter keeps current): '
  read -r health || return 0

  if [[ -n "$start" ]] && ! xo_valid_text "$start" 500; then
    XO_NOTICE="The start command must be one line."
    return 1
  fi
  if [[ -n "$health" ]] && ! xo_valid_url "$health"; then
    XO_NOTICE="The health URL must be an http or https URL."
    return 1
  fi

  new_start="$XO_CUSTOM_START"
  new_health="$XO_CUSTOM_HEALTH"
  [[ -n "$start" ]] && new_start="$start"
  [[ -n "$health" ]] && new_health="$health"

  if [[ -z "$new_start" && -z "$new_health" ]]; then
    XO_NOTICE="Custom server is unset."
    return 0
  fi
  if [[ -z "$new_start" || -z "$new_health" ]]; then
    XO_NOTICE="Custom server needs a start command and a health URL."
    return 1
  fi

  XO_CUSTOM_START="$new_start"
  XO_CUSTOM_HEALTH="$new_health"
  XO_SERVER="custom"
  if ! xo_save_settings; then
    XO_NOTICE="Could not save the custom server."
    return 1
  fi

  printf '\nCommand:\n%s\nHealth:\n%s\n' "$XO_CUSTOM_START" "$XO_CUSTOM_HEALTH"
  printf 'Quit leaves this process running.\n'
  if ! xo_confirm "Start this server?"; then
    XO_NOTICE="Custom server saved. Start was cancelled."
    return 0
  fi

  if [[ -f "$XO_VAR/custom-server.pid" ]]; then
    read -r pid < "$XO_VAR/custom-server.pid" || pid=""
    if [[ "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null; then
      xo_refresh force
      if [[ "$XO_CUSTOM_HEALTH_STATE" == up ]]; then
        XO_NOTICE="Custom server is already running."
        return 0
      fi
      XO_NOTICE="The recorded custom server process is not responding."
      return 1
    fi
  fi

  mkdir -p "$XO_LOG_DIR" || {
    XO_NOTICE="Could not create $(xo_rel "$XO_LOG_DIR")."
    return 1
  }
  nohup env PATH="$XO_PATH" bash -c "$XO_CUSTOM_START" \
    >> "$XO_LOG_DIR/custom-server.log" 2>&1 < /dev/null &
  printf '%s\n' "$!" > "$XO_VAR/custom-server.pid" || true
  xo_receipt "custom-server" "$XO_CUSTOM_START" "0" || true

  if ! xo_wait_url "$XO_CUSTOM_HEALTH" 20; then
    XO_NOTICE="Custom server did not respond. See $(xo_rel "$XO_LOG_DIR/custom-server.log")."
    return 1
  fi
  XO_CUSTOM_HEALTH_STATE="up"
  XO_NOTICE="Custom server is ready. H and O will check it."
}

xo_custom_agent_action() {
  local choice="" install="" launch=""
  printf 'Custom agent\n\n'
  printf 'Install: %s\n' "${XO_AGENT_INSTALL:-unset}"
  printf 'Launch:  %s\n' "${XO_AGENT_LAUNCH:-unset}"
  printf 'XOCHI stores these commands and adds no flags.\n'
  printf '\nSet, install, or launch (s/i/l, Enter returns): '
  read -r choice || return 0

  case "$choice" in
    "")
      XO_NOTICE="Custom agent is unchanged."
      return 0
      ;;
    s|S)
      printf 'Install command (Enter keeps current): '
      read -r install || return 0
      printf 'Launch command (Enter keeps current): '
      read -r launch || return 0
      if [[ -n "$install" ]] && ! xo_valid_text "$install" 500; then
        XO_NOTICE="The install command must be one line."
        return 1
      fi
      if [[ -n "$launch" ]] && ! xo_valid_text "$launch" 500; then
        XO_NOTICE="The launch command must be one line."
        return 1
      fi
      [[ -n "$install" ]] && XO_AGENT_INSTALL="$install"
      [[ -n "$launch" ]] && XO_AGENT_LAUNCH="$launch"
      if [[ -z "$XO_AGENT_INSTALL" && -z "$XO_AGENT_LAUNCH" ]]; then
        XO_NOTICE="Custom agent is unset."
        return 0
      fi
      if ! xo_save_settings; then
        XO_NOTICE="Could not save the custom agent."
        return 1
      fi
      XO_NOTICE="Custom agent saved."
      ;;
    i|I)
      if [[ -z "$XO_AGENT_INSTALL" ]]; then
        XO_NOTICE="No install command saved."
        return 1
      fi
      xo_run_shell "custom-install" "$XO_AGENT_INSTALL"
      ;;
    l|L)
      if [[ -z "$XO_AGENT_LAUNCH" ]]; then
        XO_NOTICE="No launch command saved."
        return 1
      fi
      xo_server_ready || return 1
      printf 'Command:\n%s\n' "$XO_AGENT_LAUNCH"
      printf 'XOCHI adds no flags.\n'
      if ! xo_confirm "Open this in Terminal?"; then
        XO_NOTICE="Cancelled."
        return 0
      fi
      xo_open_terminal "$XO_AGENT_LAUNCH" || return 1
      xo_receipt "custom-launch" "$XO_AGENT_LAUNCH" "0" || true
      XO_NOTICE="Custom agent was opened in Terminal."
      ;;
    *)
      XO_NOTICE="Use s, i, l, or Enter."
      return 1
      ;;
  esac
}
