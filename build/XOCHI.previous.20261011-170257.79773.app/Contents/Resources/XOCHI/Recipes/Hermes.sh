#!/usr/bin/env bash
# Hermes recipe. One installer. It writes ~/.hermes, which XOCHI does not own.
# Launch does not write ~/.hermes/config.yaml.

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  printf 'Run Xochi.sh instead.\n' >&2
  exit 1
fi

XO_HERMES_INSTALL="curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash"

xo_hermes_action() {
  local command
  xo_refresh force
  if [[ -z "$XO_BIN_HERMES" ]]; then
    xo_require_tools curl git || return 1
    printf 'Hermes is not installed.\n'
    printf 'This installer writes ~/.hermes and ~/.local/bin/hermes.\n'
    printf 'XOCHI keeps only the log and receipt under var/.\n'
    xo_run_shell "hermes-install" "$XO_HERMES_INSTALL" || return 1
    return 0
  fi

  xo_server_ready || return 1
  xo_warn_27b
  command="$(printf 'exec %q' "$XO_BIN_HERMES")"
  printf 'XOCHI will not change ~/.hermes/config.yaml.\n'
  printf '\nCommand:\n%s\n' "$command"
  if ! xo_confirm "Open Hermes in Terminal?"; then
    XO_NOTICE="Cancelled."
    return 0
  fi
  xo_open_terminal "$command" || return 1
  xo_receipt "hermes-launch" "$command" "0" || true
  XO_NOTICE="Hermes was opened. Its config was not changed."
}
