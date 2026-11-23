#!/usr/bin/env bash
# OpenClaw recipe. Official installer, onboarding skipped.
# Launch is the documented local terminal UI: openclaw chat.
# A gateway that installer registers is not managed here.

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  printf 'Run Xochi.sh instead.\n' >&2
  exit 1
fi

XO_OPENCLAW_INSTALL="curl -fsSL https://openclaw.ai/install.sh | bash -s -- --no-onboard"

xo_openclaw_action() {
  local command
  xo_refresh force
  if [[ -z "$XO_BIN_OPENCLAW" ]]; then
    xo_require_tools curl git || return 1
    printf 'OpenClaw is not installed.\n'
    printf 'The installer may install Node and register its own service.\n'
    printf 'XOCHI cannot stop that service. Onboarding is skipped.\n'
    xo_run_shell "openclaw-install" "$XO_OPENCLAW_INSTALL" || return 1
    return 0
  fi

  xo_server_ready || return 1
  command="$(printf 'exec %q chat' "$XO_BIN_OPENCLAW")"
  printf 'Command:\n%s\n' "$command"
  printf 'No config flags are added. A registered OpenClaw service is left alone.\n'
  if ! xo_confirm "Open OpenClaw in Terminal?"; then
    XO_NOTICE="Cancelled."
    return 0
  fi
  xo_open_terminal "$command" || return 1
  xo_receipt "openclaw-launch" "$command" "0" || true
  XO_NOTICE="OpenClaw was opened. XOCHI did not change its config."
}
