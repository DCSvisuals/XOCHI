#!/usr/bin/env bash
# Select or download an Ollama model. Hugging Face input must use hf.co
# or huggingface.co. XOCHI does not browse the Hub.

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  printf 'Run Xochi.sh instead.\n' >&2
  exit 1
fi

xo_need_ollama() {
  xo_refresh force
  if [[ -z "$XO_BIN_OLLAMA" ]]; then
    XO_NOTICE="Ollama is not installed. Press L."
    return 1
  fi
  if [[ "$XO_OLLAMA_HEALTH" != up ]]; then
    XO_NOTICE="Ollama is not responding. Press L to start it."
    return 1
  fi
  return 0
}

xo_hf_normalize() {
  local raw="$1"
  raw="${raw#"${raw%%[![:space:]]*}"}"
  raw="${raw%"${raw##*[![:space:]]}"}"
  raw="${raw#ollama pull }"
  raw="${raw#ollama run }"
  raw="${raw#https://}"
  raw="${raw#http://}"
  raw="${raw#huggingface.co/}"
  raw="${raw#hf.co/}"
  raw="${raw%%\?*}"
  raw="${raw%%/tree/*}"
  raw="${raw%%/blob/*}"
  raw="${raw%%/resolve/*}"
  raw="${raw%/}"
  printf '%s' "$raw"
}

xo_hf_is_ref() {
  [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,80}/[A-Za-z0-9][A-Za-z0-9._-]{0,120}(:[A-Za-z0-9][A-Za-z0-9._-]{0,80})?$ ]] &&
    [[ "$1" != *..* ]]
}

xo_hf_quants() {
  local repo="$1" payload
  payload="$(curl -fsS --max-time 25 -A "XOCHI" \
    "https://huggingface.co/api/models/${repo}/tree/main")" || return 1
  printf '%s' "$payload" | python3 -c '
import json, re, sys
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(2)
if not isinstance(data, list):
    sys.exit(3)
pat = re.compile(
    r"(?:^|[-_])((?:UD-)?(?:IQ|Q)\d+(?:_[0-9A-Za-z]+)*|BF16|F16|F32)$",
    re.I,
)
found = {}
for item in data:
    if not isinstance(item, dict) or item.get("type") != "file":
        continue
    path = str(item.get("path") or "")
    low = path.lower()
    if not low.endswith(".gguf"):
        continue
    if any(word in low for word in ("mmproj", "projector", "vocab")):
        continue
    if re.search(r"\d+-of-\d+", low):
        continue
    try:
        size = int(item.get("size") or 0)
    except Exception:
        size = 0
    if 0 < size < 10000000:
        continue
    stem = path[:-5]
    match = pat.search(stem)
    tag = match.group(1) if match else stem
    key = tag.upper()
    current = found.get(key)
    if current is None or size > current[1]:
        found[key] = (tag, size)
rows = list(found.values())
rows.sort(key=lambda row: (row[1] == 0, row[1], row[0].upper()))
preferred, rest = [], []
for tag, size in rows:
    if tag.upper() in ("Q4_K_M", "Q5_K_M", "Q6_K", "Q8_0", "Q4_K_S"):
        preferred.append((tag, size))
    else:
        rest.append((tag, size))
for tag, size in (preferred + rest)[:18]:
    print("%s\t%d" % (tag, size))
'
}

xo_save_model() {
  local name="$1"
  xo_valid_model "$name" || {
    XO_NOTICE="The model name is not valid."
    return 1
  }
  XO_MODEL="$name"
  if ! xo_save_settings; then
    XO_NOTICE="The model was not saved."
    return 1
  fi
  XO_NOTICE="Model is ${XO_MODEL}."
}

xo_select_model() {
  local output name id size unit rest choice n i
  local -a names=() sizes=()
  xo_need_ollama || return 1
  output="$(env OLLAMA_HOST="$XO_OLLAMA_URL" "$XO_BIN_OLLAMA" list)" || {
    XO_NOTICE="Could not list models."
    return 1
  }
  while read -r name id size unit rest; do
    [[ "$name" == NAME || -z "$name" ]] && continue
    [[ "$name" == hermes-active || "$name" == hermes-active:latest ]] && continue
    xo_valid_model "$name" || continue
    names+=("$name")
    if [[ "$unit" == GB || "$unit" == GiB || "$unit" == MB || "$unit" == MiB || "$unit" == TB ]]; then
      sizes+=("${size} ${unit}")
    else
      sizes+=("")
    fi
  done <<< "$output"
  (( ${#names[@]} > 0 )) || {
    XO_NOTICE="No installed models. Press D to download one."
    return 1
  }
  printf 'Select model\n\n'
  for ((i=0; i<${#names[@]}; i++)); do
    printf '%3d) %s' "$((i + 1))" "${names[$i]}"
    [[ -n "${sizes[$i]}" ]] && printf '  %s' "${sizes[$i]}"
    [[ "${names[$i]}" == "$XO_MODEL" ]] && printf ' [selected]'
    printf '\n'
  done
  printf '\nNumber (Enter cancels): '
  read -r choice || return 0
  [[ -z "$choice" ]] && return 0
  [[ "$choice" =~ ^[0-9]{1,6}$ ]] || {
    XO_NOTICE="Enter a model number."
    return 1
  }
  n=$((10#$choice))
  (( n >= 1 && n <= ${#names[@]} )) || {
    XO_NOTICE="Model selection is out of range."
    return 1
  }
  xo_save_model "${names[$((n - 1))]}"
}

xo_download_model() {
  local raw="" norm="" repo="" quant="" target="" bytes="0"
  local output tag size choice i n upper default_index=-1
  local -a tags=() sizes=()
  xo_need_ollama || return 1
  printf 'Download model\n\n'
  printf 'Ollama name, for example qwen3.6:27b\n'
  printf 'Hugging Face GGUF, for example hf.co/user/repo:Q4_K_M\n'
  printf 'A Hugging Face repo with no quant asks you to pick one.\n'
  printf '\nName (Enter cancels): '
  read -r raw || return 0
  [[ -z "$raw" ]] && return 0
  xo_valid_text "$raw" 300 || {
    XO_NOTICE="That name must be one line."
    return 1
  }

  if [[ "$raw" == *hf.co* || "$raw" == *huggingface.co* ]]; then
    norm="$(xo_hf_normalize "$raw")"
    xo_hf_is_ref "$norm" || {
      XO_NOTICE="That Hugging Face reference is not valid."
      return 1
    }
    repo="${norm%%:*}"
    quant=""
    [[ "$norm" == *:* ]] && quant="${norm#*:}"
    if [[ -z "$quant" ]]; then
      output="$(xo_hf_quants "$repo")" || {
        XO_NOTICE="Could not read GGUF files for ${repo}."
        return 1
      }
      while IFS=$'\t' read -r tag size; do
        [[ -n "$tag" ]] || continue
        tags+=("$tag")
        sizes+=("$size")
        [[ "$(printf '%s' "$tag" | tr '[:lower:]' '[:upper:]')" == Q4_K_M ]] &&
          default_index=$((${#tags[@]} - 1))
      done <<< "$output"
      (( ${#tags[@]} > 0 )) || {
        XO_NOTICE="No single GGUF quant was found. Include the quant in the name."
        return 1
      }
      printf '\nQuantization:\n'
      for ((i=0; i<${#tags[@]}; i++)); do
        printf '%3d) %s  %s' "$((i + 1))" "${tags[$i]}" "$(xo_size_gib "${sizes[$i]}")"
        (( i == default_index )) && printf ' [default]'
        printf '\n'
      done
      printf '\nNumber or name (Enter uses the default): '
      read -r choice || return 0
      if [[ -z "$choice" ]]; then
        if (( default_index >= 0 )); then
          quant="${tags[$default_index]}"
          bytes="${sizes[$default_index]}"
        else
          quant="${tags[0]}"
          bytes="${sizes[0]}"
        fi
      elif [[ "$choice" =~ ^[0-9]{1,6}$ ]]; then
        n=$((10#$choice))
        (( n >= 1 && n <= ${#tags[@]} )) || {
          XO_NOTICE="Quant selection is out of range."
          return 1
        }
        quant="${tags[$((n - 1))]}"
        bytes="${sizes[$((n - 1))]}"
      else
        upper="$(printf '%s' "$choice" | tr '[:lower:]' '[:upper:]')"
        quant=""
        for ((i=0; i<${#tags[@]}; i++)); do
          if [[ "$(printf '%s' "${tags[$i]}" | tr '[:lower:]' '[:upper:]')" == "$upper" ]]; then
            quant="${tags[$i]}"
            bytes="${sizes[$i]}"
            break
          fi
        done
        [[ -n "$quant" ]] || {
          XO_NOTICE="That quant is not in the list."
          return 1
        }
      fi
    else
      output="$(xo_hf_quants "$repo" 2>/dev/null || true)"
      upper="$(printf '%s' "$quant" | tr '[:lower:]' '[:upper:]')"
      while IFS=$'\t' read -r tag size; do
        if [[ "$(printf '%s' "$tag" | tr '[:lower:]' '[:upper:]')" == "$upper" ]]; then
          bytes="$size"
          break
        fi
      done <<< "$output"
    fi
    quant="$(printf '%s' "$quant" | tr '[:lower:]' '[:upper:]')"
    target="hf.co/${repo}:${quant}"
  else
    target="$(xo_hf_normalize "$raw")"
  fi

  xo_valid_model "$target" || {
    XO_NOTICE="That model name is not valid."
    return 1
  }
  printf '\nOllama name: %s\n' "$target"
  xo_report_fit "$bytes"
  printf '\n'
  xo_run_shell "model-pull" "env OLLAMA_HOST=${XO_OLLAMA_URL} $(printf '%q' "$XO_BIN_OLLAMA") pull $(printf '%q' "$target")" || return 1
  [[ "$XO_NOTICE" == "Cancelled." ]] && return 0
  xo_save_model "$target" || return 1
  XO_NOTICE="Downloaded and selected ${target}."
}
