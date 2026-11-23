#!/usr/bin/env bash
# XOCHI dashboard. Same card, left-hand keys, and gold status as the personal launcher.

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  printf 'Run Xochi.sh instead.\n' >&2
  exit 1
fi

XO_ROWS=24
XO_COLS=80
XO_PANEL_W=76
XO_TEXT_W=40
XO_SHOW_LOGO=0
XO_MARGIN="  "
XO_SCREEN_ACTIVE=0

XO_LOGO=(
  "      ····      "
  "   ··      ··   "
  "  ·   ····   ·  "
  " ·  ·      ·  · "
  "·  ·    o   ·  ·"
  " ·  ·      ·  · "
  "  ·   ····   ·  "
  "   ··      ··   "
  "      ····      "
)

xo_spaces() {
  local n="$1"
  (( n < 1 )) && return 0
  printf '%*s' "$n" ''
}

xo_rule() {
  local n="$1" i out=""
  (( n < 1 )) && return 0
  for ((i=0; i<n; i++)); do
    out+="─"
  done
  printf '%s' "$out"
}

xo_clip() {
  local text="$1" width="$2"
  (( width < 1 )) && return 0
  if (( ${#text} <= width )); then
    printf '%s' "$text"
  elif (( width == 1 )); then
    printf '…'
  else
    printf '%s…' "${text:0:width-1}"
  fi
}

xo_logo_colored() {
  local plain="$1" left right
  left="${plain%%o*}"
  if [[ "$plain" == "$left" ]]; then
    printf '%s%s%s' "$XO_MUTED" "$plain" "$XO_RESET"
    return 0
  fi
  right="${plain#*o}"
  printf '%s%s%s%s%s%s' \
    "$XO_MUTED" "$left" "$XO_GOLD" "o" "$XO_MUTED" "$right$XO_RESET"
}

xo_read_size() {
  local rows cols reported
  reported="$(
    (stty size </dev/tty || stty size || printf '24 80\n') 2>/dev/null
  )" || reported="24 80"
  read -r rows cols <<< "$reported"
  [[ "$rows" =~ ^[0-9]+$ ]] || rows=24
  [[ "$cols" =~ ^[0-9]+$ ]] || cols=80
  (( rows < 8 )) && rows=8
  (( cols < 20 )) && cols=20
  XO_ROWS="$rows"
  XO_COLS="$cols"
}

xo_push_row() {
  local plain="$1" colored="$2"
  local logo_plain="" logo_colored="" combined_plain combined_colored inner pad

  inner=$((XO_PANEL_W - 2))
  if (( XO_SHOW_LOGO )); then
    if (( XO_ROW_INDEX < ${#XO_LOGO[@]} )); then
      logo_plain="${XO_LOGO[$XO_ROW_INDEX]}"
    else
      logo_plain="$(xo_spaces 16)"
    fi
    logo_colored="$(xo_logo_colored "$logo_plain")"
    combined_plain="${logo_plain}  ${plain}"
    combined_colored="${logo_colored}  ${colored}"
  else
    combined_plain=" ${plain}"
    combined_colored=" ${colored}"
  fi
  XO_ROW_INDEX=$((XO_ROW_INDEX + 1))

  if (( ${#combined_plain} > inner )); then
    combined_plain="$(xo_clip "$combined_plain" "$inner")"
    combined_colored="${XO_BODY}${combined_plain}${XO_RESET}"
  fi
  pad=$((inner - ${#combined_plain}))
  (( pad < 0 )) && pad=0
  XO_LINES+=("$(printf '%s│%s%s%s%s│%s' \
    "$XO_BORDER" "$XO_RESET" "$combined_colored" "$(xo_spaces "$pad")" \
    "$XO_BORDER" "$XO_RESET")")
}

xo_add_text() {
  local text="$1" color="$2" gap spaces
  text="$(xo_clip "$text" "$XO_TEXT_W")"
  gap=$((XO_TEXT_W - ${#text}))
  (( gap < 0 )) && gap=0
  spaces="$(xo_spaces "$gap")"
  xo_push_row "${text}${spaces}" "${color}${text}${XO_RESET}${spaces}"
}

xo_add_blank() {
  local spaces
  spaces="$(xo_spaces "$XO_TEXT_W")"
  xo_push_row "$spaces" "$spaces"
}

xo_add_title() {
  local name="XOCHI" ver="$XO_VERSION" plain gap spaces colored
  plain="${name}  ${ver}"
  if (( ${#plain} > XO_TEXT_W )); then
    plain="$(xo_clip "$name" "$XO_TEXT_W")"
    colored="${XO_WHITE}${plain}${XO_RESET}"
  else
    colored="${XO_WHITE}${name}${XO_RESET}  ${XO_MUTED}${ver}${XO_RESET}"
  fi
  gap=$((XO_TEXT_W - ${#plain}))
  (( gap < 0 )) && gap=0
  spaces="$(xo_spaces "$gap")"
  xo_push_row "${plain}${spaces}" "${colored}${spaces}"
}

xo_add_menu() {
  local label="$1" key="$2" prefix gap spaces plain colored keep
  prefix="${key}  "
  if (( ${#prefix} + ${#label} > XO_TEXT_W )); then
    keep=$((XO_TEXT_W - ${#prefix}))
    (( keep < 1 )) && keep=1
    label="$(xo_clip "$label" "$keep")"
  fi
  plain="${prefix}${label}"
  gap=$((XO_TEXT_W - ${#plain}))
  (( gap < 0 )) && gap=0
  spaces="$(xo_spaces "$gap")"
  colored="${XO_MUTED}${key}${XO_RESET}  ${XO_WHITE}${label}${XO_RESET}"
  xo_push_row "${plain}${spaces}" "${colored}${spaces}"
}

xo_border() {
  local edge="$1" left right fill target="${3:-lines}"
  case "$edge" in
    top) left="╭"; right="╮" ;;
    *) left="╰"; right="╯" ;;
  esac
  fill="$(xo_rule $((XO_PANEL_W - 2)))"
  if [[ "$target" == foot ]]; then
    XO_FOOT+=("${XO_BORDER}${left}${fill}${right}${XO_RESET}")
  else
    XO_LINES+=("${XO_BORDER}${left}${fill}${right}${XO_RESET}")
  fi
}

xo_prepare_view() {
  local missing=""
  [[ -z "$XO_BIN_BREW" ]] && missing="${missing:+$missing, }brew"
  [[ -z "$XO_BIN_GIT" ]] && missing="${missing:+$missing, }git"
  [[ -z "$XO_BIN_CURL" ]] && missing="${missing:+$missing, }curl"
  if [[ -n "$missing" ]]; then
    XO_TOOLS_LINE="Missing tools: ${missing}"
  else
    XO_TOOLS_LINE=""
  fi

  if [[ -n "$XO_BIN_OLLAMA" ]]; then
    XO_OLLAMA_LINE="Ollama installed"
  else
    XO_OLLAMA_LINE="Ollama missing"
  fi
  if [[ -n "$XO_BIN_HERMES" ]]; then
    XO_HERMES_LINE="Hermes installed"
  else
    XO_HERMES_LINE="Hermes missing"
  fi
  if [[ -n "$XO_BIN_OPENCLAW" ]]; then
    XO_OPENCLAW_LINE="OpenClaw installed"
  else
    XO_OPENCLAW_LINE="OpenClaw missing"
  fi

  if [[ "$XO_SERVER" == custom ]]; then
    if [[ -z "$XO_CUSTOM_HEALTH" ]]; then
      XO_SERVER_LINE="Server custom unset"
      XO_HEADLINE="Server is not ready"
    elif [[ "$XO_CUSTOM_HEALTH_STATE" == up ]]; then
      XO_SERVER_LINE="Server custom ready"
      XO_HEADLINE="Server is ready"
    else
      XO_SERVER_LINE="Server custom down"
      XO_HEADLINE="Server is not ready"
    fi
    XO_SUBTITLE="custom  ·  ${XO_CUSTOM_HEALTH:-no health URL}"
  else
    if [[ "$XO_OLLAMA_HEALTH" == up ]]; then
      XO_SERVER_LINE="Server ollama ready"
      XO_HEADLINE="Server is ready"
    else
      XO_SERVER_LINE="Server ollama down"
      XO_HEADLINE="Server is not ready"
    fi
    XO_SUBTITLE="ollama  ·  ${XO_OLLAMA_URL}"
  fi

  if [[ "$XO_CPU_PCT" =~ ^[0-9]+$ ]]; then
    XO_RESOURCE_LINE="RAM ${XO_USED_GIB} / ${XO_TOTAL_GIB} GiB  ·  CPU ${XO_CPU_PCT}%"
  else
    XO_RESOURCE_LINE="RAM ${XO_USED_GIB} / ${XO_TOTAL_GIB} GiB  ·  CPU ${XO_CPU_PCT}"
  fi
  if [[ -n "$XO_MODEL" ]]; then
    XO_MODEL_LINE="Model ${XO_MODEL}"
  else
    XO_MODEL_LINE="Model not selected"
  fi

  XO_MENU_LABELS=()
  XO_MENU_KEYS=()
  if [[ -n "$XO_BIN_HERMES" ]]; then
    XO_MENU_LABELS+=("Launch Hermes")
  else
    XO_MENU_LABELS+=("Install Hermes")
  fi
  if [[ -n "$XO_BIN_OPENCLAW" ]]; then
    XO_MENU_LABELS+=("Launch OpenClaw")
  else
    XO_MENU_LABELS+=("Install OpenClaw")
  fi
  if [[ -z "$XO_BIN_OLLAMA" ]]; then
    XO_MENU_LABELS+=("Install Ollama")
  elif [[ "$XO_OLLAMA_HEALTH" == up ]]; then
    XO_MENU_LABELS+=("Ollama running")
  else
    XO_MENU_LABELS+=("Start Ollama")
  fi
  XO_MENU_LABELS+=("Select model" "Download model" "Custom server" "Custom agent" "Quit")
  XO_MENU_KEYS=("H" "O" "L" "M" "D" "S" "A" "Q")
}

xo_line_color() {
  case "$1" in
    *"installed"|*"ready") printf '%s' "$XO_OK" ;;
    *"missing"|*"down"|*"unset"|Missing*) printf '%s' "$XO_BAD" ;;
    *) printf '%s' "$XO_MUTED" ;;
  esac
}

xo_footer_prompt() {
  local inner notice right prefix left gap spaces plain colored keep
  inner=$((XO_PANEL_W - 2))
  notice="$XO_NOTICE"
  if [[ -n "$XO_MODEL" ]]; then
    right="${XO_MODEL} "
  else
    right="no model "
  fi
  if (( ${#right} > 28 )); then
    right="$(xo_clip "${right% }" 27) "
  fi
  prefix=" > "
  keep=$((inner - ${#prefix} - ${#right}))
  (( keep < 0 )) && keep=0
  notice="$(xo_clip "$notice" "$keep")"
  left="${prefix}${notice}"
  gap=$((inner - ${#left} - ${#right}))
  (( gap < 0 )) && gap=0
  spaces="$(xo_spaces "$gap")"
  plain="${left}${spaces}${right}"
  if (( ${#plain} > inner )); then
    plain="$(xo_clip "$plain" "$inner")"
    colored="${XO_BODY}${plain}${XO_RESET}"
  else
    colored=" ${XO_MUTED}>${XO_RESET} ${XO_BODY}${notice}${XO_RESET}${spaces}${XO_MUTED}${right}${XO_RESET}"
  fi
  XO_FOOT+=("$(printf '%s│%s%s%s│%s' \
    "$XO_BORDER" "$XO_RESET" "$colored" "$XO_BORDER" "$XO_RESET")")
}

xo_footer_badge() {
  local badge="[setup]" pad
  pad=$((XO_PANEL_W - ${#badge}))
  (( pad < 0 )) && pad=0
  XO_FOOT+=("$(printf '%s%s%s%s' \
    "$XO_MUTED" "$(xo_spaces "$pad")" "$badge" "$XO_RESET")")
}

xo_render() {
  local margin inner spare card_rows footer_rows menu_rows budget
  local show_tools=0 show_ollama=0 show_hermes=0 show_openclaw=0 show_server=0
  local show_resources=0 show_model=0
  local show_header_gap=0 show_quit_gap=0 show_badge=0 i gap line frame color

  xo_prepare_view
  margin=2
  (( XO_COLS < 56 )) && margin=1
  (( XO_COLS < 44 )) && margin=0
  XO_PANEL_W=$((XO_COLS - margin * 2))
  (( XO_PANEL_W >= XO_COLS )) && XO_PANEL_W=$((XO_COLS - 1))
  (( XO_PANEL_W < 24 )) && XO_PANEL_W=$((XO_COLS > 24 ? 24 : XO_COLS - 1))
  XO_MARGIN="$(xo_spaces "$margin")"

  XO_SHOW_LOGO=0
  (( XO_COLS >= 92 && XO_ROWS >= 32 )) && XO_SHOW_LOGO=1
  inner=$((XO_PANEL_W - 2))
  if (( XO_SHOW_LOGO )); then
    XO_TEXT_W=$((inner - 18))
  else
    XO_TEXT_W=$((inner - 1))
  fi
  if (( XO_TEXT_W < 28 )); then
    XO_SHOW_LOGO=0
    XO_TEXT_W=$((inner - 1))
  fi
  (( XO_TEXT_W > 12 )) && XO_TEXT_W=$((XO_TEXT_W - 1))
  (( XO_TEXT_W < 8 )) && XO_TEXT_W=8

  menu_rows=${#XO_MENU_LABELS[@]}
  card_rows=$((5 + menu_rows))
  footer_rows=4
  show_badge=0
  if (( XO_ROWS >= 32 )); then
    show_badge=1
    footer_rows=5
  fi
  budget=$((XO_ROWS - 1))
  spare=$((budget - card_rows - footer_rows))

  if (( spare >= 1 )); then
    show_resources=1
    spare=$((spare - 1))
  fi
  if (( spare >= 1 )); then
    show_model=1
    spare=$((spare - 1))
  fi
  if (( spare >= 1 )); then
    show_server=1
    spare=$((spare - 1))
  fi
  if [[ -n "$XO_TOOLS_LINE" ]] && (( spare >= 1 )); then
    show_tools=1
    spare=$((spare - 1))
  fi
  if (( spare >= 1 )); then
    show_ollama=1
    spare=$((spare - 1))
  fi
  if (( spare >= 1 )); then
    show_hermes=1
    spare=$((spare - 1))
  fi
  if (( spare >= 1 )); then
    show_openclaw=1
    spare=$((spare - 1))
  fi
  if (( spare >= 1 )); then
    show_header_gap=1
    spare=$((spare - 1))
  fi
  if (( spare >= 1 )); then
    show_quit_gap=1
    spare=$((spare - 1))
  fi
  (( spare < 0 )) && spare=0

  XO_LINES=()
  XO_FOOT=()
  XO_ROW_INDEX=0
  xo_border top
  xo_add_title
  xo_add_text "$XO_HEADLINE" "$XO_GOLD"
  xo_add_text "$XO_SUBTITLE" "$XO_MUTED"
  if (( show_resources )); then
    xo_add_text "$XO_RESOURCE_LINE" "$XO_MUTED"
  fi
  if (( show_model )); then
    xo_add_text "$XO_MODEL_LINE" "$XO_MUTED"
  fi

  if (( show_tools )); then
    xo_add_text "$XO_TOOLS_LINE" "$XO_BAD"
  fi
  if (( show_ollama )); then
    color="$(xo_line_color "$XO_OLLAMA_LINE")"
    xo_add_text "$XO_OLLAMA_LINE" "$color"
  fi
  if (( show_hermes )); then
    color="$(xo_line_color "$XO_HERMES_LINE")"
    xo_add_text "$XO_HERMES_LINE" "$color"
  fi
  if (( show_openclaw )); then
    color="$(xo_line_color "$XO_OPENCLAW_LINE")"
    xo_add_text "$XO_OPENCLAW_LINE" "$color"
  fi
  if (( show_server )); then
    color="$(xo_line_color "$XO_SERVER_LINE")"
    xo_add_text "$XO_SERVER_LINE" "$color"
  fi
  if (( show_header_gap )); then
    xo_add_blank
  fi

  for ((i=0; i<menu_rows; i++)); do
    if (( show_quit_gap && i == menu_rows - 1 )); then
      xo_add_blank
    fi
    xo_add_menu "${XO_MENU_LABELS[$i]}" "${XO_MENU_KEYS[$i]}"
  done
  xo_border bottom

  XO_FOOT+=("${XO_MUTED}$(xo_clip "Tip: Q leaves servers and agents running. Commands wait for y." "$XO_PANEL_W")${XO_RESET}")
  xo_border top "" foot
  xo_footer_prompt
  xo_border bottom "" foot
  if (( show_badge )); then
    xo_footer_badge
  fi

  frame=""
  for ((i=0; i<${#XO_LINES[@]}; i++)); do
    frame+="${XO_MARGIN}${XO_LINES[$i]}"$'\n'
  done
  for ((i=0; i<spare; i++)); do
    frame+=$'\n'
  done
  for ((i=0; i<${#XO_FOOT[@]}; i++)); do
    frame+="${XO_MARGIN}${XO_FOOT[$i]}"$'\n'
  done
  printf '%s' "$frame"
}

xo_draw() {
  local frame output
  frame="$(xo_render)"
  output="${frame//$'\n'/$'\033[K\n'}"
  printf '\033[?25l\033[H%s\033[J' "$output"
}
