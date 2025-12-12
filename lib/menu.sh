#!/usr/bin/env bash

# Single-select menu
# Usage: menu_select_one "Prompt" "Header" result_var "${array[@]}"
menu_select_one() {
  local prompt="$1"
  local header="$2"
  local __result_var="$3"
  shift 3
  local items=("$@")

  if [[ ${#items[@]} -eq 0 ]]; then
    log_error "menu_select_one: no items provided"
    return 1
  fi

  log_debug "menu_select_one: ${#items[@]} items"

  local selection=""
  if command -v fzf >/dev/null 2>&1; then
    selection=$(printf '%s\n' "${items[@]}" |
      fzf --prompt="${prompt}: " \
          --header="${header}" \
          --height=50% --reverse)

    if [[ -z "$selection" ]]; then
      log_info "Selection cancelled"
      return 1
    fi
  else
    log_warn "fzf not available, falling back to select UI"
    PS3="${prompt} ${header} (0=cancel): "
    select sel in "${items[@]}"; do
      case "$REPLY" in
        0) log_info "Selection cancelled"; return 1 ;;
        '') echo "Invalid selection" ;;
        *) selection="$sel"; break ;;
      esac
    done
  fi

  printf -v "$__result_var" "%s" "$selection"
  log_info "Selected: $selection"
  return 0
}

# Multi-select
# Usage: menu_select_multi "Prompt" result_var "${array[@]}"
menu_select_multi() {
  local prompt="$1"
  local __result_var="$2"
  shift 2
  local items=("$@")

  if [[ ${#items[@]} -eq 0 ]]; then
    log_error "menu_select_multi: no items provided"
    return 1
  fi

  local selections=""

  if command -v fzf >/dev/null 2>&1; then
    selections=$(printf '%s\n' "${items[@]}" |
      fzf --multi \
          --prompt="${prompt}: " \
          --header="${prompt} (Tab=mark, Enter=confirm)" \
          --bind 'enter:toggle+accept' \
          --height=50% --reverse)

    if [[ -z "$selections" ]]; then
      log_info "Multi-select cancelled"
      return 1
    fi
  else
    log_warn "fzf not installed; using repeated select-based multi-select"
    local chosen=()
    while true; do
      echo
      PS3="${prompt} (0=done): "
      select sel in "${items[@]}"; do
        case "$REPLY" in
          0) selections=$(printf "%s\n" "${chosen[@]}"); break 2 ;;
          '') echo "Invalid selection" ;;
          *) chosen+=("$sel"); break ;;
        esac
      done
    done
  fi

  log_debug "menu_select_multi selected: [$selections]"
  declare -g "$__result_var=$selections"
  return 0
}
