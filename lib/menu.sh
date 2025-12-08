#!/usr/bin/env bash

# Select a single item from stdin or array
# Usage: menu_select_one "Prompt" "Header" result_var "${array[@]}"
menu_select_one() {
  local prompt="$1"
  local header="$2"
  local __result_var="$3"
  shift 3
  local items=("$@")

  if [[ ${#items[@]} -eq 0 ]]; then
    log_error "No items to select from in menu_select_one"
    return 1
  fi

  local selection=""
  if command -v fzf >/dev/null 2>&1; then
    selection=$(printf '%s\n' "${items[@]}" | fzf --prompt="${prompt}: " --height=~50% --reverse --header="${header}")
    if [[ -z "$selection" ]]; then
      log_info "No selection made (fzf cancelled)"
      return 1
    fi
  else
    PS3="${prompt} ${header} (0 to cancel): "
    select sel in "${items[@]}"; do
      if [[ "$REPLY" == "0" ]]; then
        log_info "Selection cancelled"
        return 1
      elif [[ -z "$sel" ]]; then
        echo "\"$REPLY\" is not a valid choice" >&2
      else
        selection="$sel"
        break
      fi
    done
  fi

  printf -v "$__result_var" '%s' "$selection"
  return 0
}

# Multi-select using fzf; falls back to single-select loop if fzf missing
# Usage: menu_select_multi "Prompt" result_var "${array[@]}"
menu_select_multi() {
  local prompt="$1"
  local __result_var="$2"
  shift 2
  local items=("$@")

  if [[ ${#items[@]} -eq 0 ]]; then
    log_error "No items to select from in menu_select_multi"
    return 1
  fi

  local selections=""
  if command -v fzf >/dev/null 2>&1; then
    # In multi mode, pressing Enter without Tab marking returns nothing
    # So we bind Enter to: toggle current item + accept
    [[ -n "${DEBUG_AWS_SSM:-}" ]] && echo "DEBUG: About to run fzf with ${#items[@]} items" >&2
    selections=$(printf '%s\n' "${items[@]}" |
      fzf --multi --prompt="${prompt}: " --height=~50% --reverse \
        --header="${prompt} (Tab to mark multiple, Enter to confirm)" \
        --bind 'enter:toggle+accept')
    local fzf_exit=$?
    [[ -n "${DEBUG_AWS_SSM:-}" ]] && echo "DEBUG: fzf exit code: $fzf_exit" >&2
    [[ -n "${DEBUG_AWS_SSM:-}" ]] && echo "DEBUG: fzf returned: [$selections]" >&2
    [[ -n "${DEBUG_AWS_SSM:-}" ]] && echo "DEBUG: fzf returned length: ${#selections}" >&2
    if [[ $fzf_exit -ne 0 ]] || [[ -z "$selections" ]]; then
      log_info "No selection made (fzf cancelled)"
      return 1
    fi
  else
    log_warn "fzf not installed; using single-select menu (repeat to select multiple)"
    local chosen=()
    while true; do
      PS3="${prompt} (0 to finish): "
      select sel in "${items[@]}"; do
        if [[ "$REPLY" == "0" ]]; then
          selections=$(printf '%s\n' "${chosen[@]}")
          break 2
        elif [[ -z "$sel" ]]; then
          echo "\"$REPLY\" is not a valid choice" >&2
        else
          chosen+=("$sel")
          break
        fi
      done
    done
  fi

  # Use declare -g to set in caller's scope (global)
  [[ -n "${DEBUG_AWS_SSM:-}" ]] && echo "DEBUG: Before declare -g, selections=[$selections]" >&2
  declare -g "$__result_var=$selections"
  [[ -n "${DEBUG_AWS_SSM:-}" ]] && echo "DEBUG: After declare -g $__result_var" >&2
  return 0
}
