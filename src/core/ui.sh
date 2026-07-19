#!/usr/bin/env bash

UI_WIDTH=80
UI_LABEL_WIDTH=18

ui_detect_width() {
  local columns="80"
  if command_exists tput; then
    columns="$(tput cols 2>/dev/null || printf '80')"
  fi
  [[ "$columns" =~ ^[0-9]+$ ]] || columns=80
  (( columns < 64 )) && columns=64
  (( columns > 100 )) && columns=100
  UI_WIDTH="$columns"
}

ui_clear() {
  if [[ -t 1 ]] && command_exists clear; then clear; fi
}

ui_repeat() {
  local character="$1" count="$2" line
  (( count > 0 )) || return 0
  printf -v line '%*s' "$count" ''
  printf '%s' "${line// /$character}"
}

ui_display_width() {
  local value="$1" width
  width="$(printf '%s' "$value" | wc -L 2>/dev/null | tr -d '[:space:]')"
  [[ "$width" =~ ^[0-9]+$ ]] || width="${#value}"
  printf '%s' "$width"
}

ui_pad() {
  local value="$1" target="$2" width padding
  width="$(ui_display_width "$value")"
  padding=$((target - width))
  printf '%s' "$value"
  if (( padding > 0 )); then ui_repeat ' ' "$padding"; else printf ' '; fi
}

ui_color_for_state() {
  case "${1:-neutral}" in
    good|success) printf '%s' "$GREEN" ;;
    warn|warning) printf '%s' "$YELLOW" ;;
    bad|danger) printf '%s' "$RED" ;;
    primary) printf '%s' "$CYAN" ;;
    accent) printf '%s' "$MAGENTA" ;;
    action) printf '%s' "$BLUE" ;;
    muted|disabled) printf '%s' "$MUTED" ;;
    *) printf '%s' "$WHITE" ;;
  esac
}

ui_rule() {
  local first=10 second
  (( UI_WIDTH < first )) && first="$UI_WIDTH"
  second=$((UI_WIDTH - first))
  printf '%b' "$MAGENTA"
  ui_repeat '━' "$first"
  printf '%b' "$CYAN"
  ui_repeat '━' "$second"
  printf '%b\n' "$NC"
}

ui_page() {
  local title="$1" subtitle="${2:-}"
  ui_clear
  ui_detect_width
  printf '\n%b◆%b %bSERVER TOOLKIT%b %b›%b %b%s%b\n' \
    "$MAGENTA$BOLD" "$NC" "$MUTED$BOLD" "$NC" "$MAGENTA" "$NC" "$CYAN$BOLD" "$title" "$NC"
  if [[ -n "$subtitle" ]]; then
    printf '  %b%s%b\n' "$MUTED" "$subtitle" "$NC"
  fi
  ui_rule
}

ui_header() {
  printf '\n%b◇%b %b%s%b\n' "$MAGENTA" "$NC" "$CYAN$BOLD" "$1" "$NC"
  ui_rule
}

ui_badge() {
  local label="$1" color="${2:-$GREEN}"
  printf '%b●%b %b%s%b' "$color" "$NC" "$color$BOLD" "$label" "$NC"
}

ui_banner() {
  ui_clear
  ui_detect_width
  printf '\n  %b◆ SERVER%b %bTOOLKIT%b  %bv%s%b\n' \
    "$MAGENTA$BOLD" "$NC" "$CYAN$BOLD" "$NC" "$YELLOW" "$SERVERCTL_VERSION" "$NC"
  printf '  %bDebian / Ubuntu · 安全、清晰、可恢复的 VPS 控制台%b\n' "$MUTED" "$NC"
  ui_rule
}

ui_context() { printf '  %b›%b %b%s%b\n' "$MAGENTA" "$NC" "$MUTED" "$1" "$NC"; }

ui_item() {
  local number="$1" title="$2" hint="${3:-}" number_color="$CYAN" title_color="$BLUE" marker="›" hint_width=0
  if [[ "$number" == "0" ]]; then
    number_color="$MUTED"; title_color="$MUTED"; marker="←"
  fi
  printf '  %b%s%b %b[%2s]%b  %b' "$MAGENTA" "$marker" "$NC" "$number_color$BOLD" "$number" "$NC" "$title_color$BOLD"
  ui_pad "$title" 22
  printf '%b' "$NC"
  if [[ -n "$hint" ]]; then
    hint_width="$(ui_display_width "$hint")"
    if (( hint_width > UI_WIDTH - 34 )); then
      printf '\n         %b└─ %s%b' "$MUTED" "$hint" "$NC"
    else
      printf ' %b%s%b' "$MUTED" "$hint" "$NC"
    fi
  fi
  printf '\n'
}

ui_action() {
  local number="$1" title="$2" style="${3:-action}" hint="${4:-}" color hint_width=0
  color="$(ui_color_for_state "$style")"
  printf '  %b[%s]%b  %b' "$color$BOLD" "$number" "$NC" "$color$BOLD"
  ui_pad "$title" 18
  printf '%b' "$NC"
  if [[ -n "$hint" ]]; then
    hint_width="$(ui_display_width "$hint")"
    if (( hint_width > UI_WIDTH - 28 )); then
      printf '\n       %b└─ %s%b' "$MUTED" "$hint" "$NC"
    else
      printf ' %b%s%b' "$MUTED" "$hint" "$NC"
    fi
  fi
  printf '\n'
}

ui_kv() {
  local label="$1" value="$2" value_color="${3:-$WHITE}"
  printf '  %b' "$BLUE"
  ui_pad "$label" "$UI_LABEL_WIDTH"
  printf '%b%b%s%b\n' "$NC" "$value_color" "$value" "$NC"
}

ui_status() {
  local label="$1" value="$2" state="${3:-neutral}" color
  color="$(ui_color_for_state "$state")"
  ui_kv "$label" "● $value" "$color"
}

ui_progress() {
  local label="$1" current="$2" total="$3" unit="${4:-}" percent=0 filled empty color="$GREEN"
  if [[ "$current" =~ ^[0-9]+$ && "$total" =~ ^[0-9]+$ ]] && (( total > 0 )); then
    percent=$((current * 100 / total))
  fi
  (( percent > 100 )) && percent=100
  (( percent >= 70 )) && color="$YELLOW"
  (( percent >= 90 )) && color="$RED"
  filled=$((percent * 16 / 100))
  empty=$((16 - filled))
  printf '  %b' "$BLUE"
  ui_pad "$label" "$UI_LABEL_WIDTH"
  printf '%b%b' "$NC" "$color"
  ui_repeat '█' "$filled"
  printf '%b%b' "$NC" "$MUTED"
  ui_repeat '░' "$empty"
  printf '%b  %b%3s%%%b  %s/%s %s\n' "$NC" "$color" "$percent" "$NC" "$current" "$total" "$unit"
}

ui_section() {
  local title="$1" style="${2:-accent}" color
  color="$(ui_color_for_state "$style")"
  printf '\n%b◆%b %b%s%b\n' "$color" "$NC" "$color$BOLD" "$title" "$NC"
}

ui_panel_begin() {
  printf '\n%b╭─%b %b%s%b\n' "$MAGENTA" "$NC" "$CYAN$BOLD" "$1" "$NC"
}

ui_panel_kv() {
  local label="$1" value="$2" value_color="${3:-$WHITE}"
  printf '%b│%b  %b' "$MAGENTA" "$NC" "$BLUE"
  ui_pad "$label" "$UI_LABEL_WIDTH"
  printf '%b%b%s%b\n' "$NC" "$value_color" "$value" "$NC"
}

ui_panel_end() { printf '%b╰%b\n' "$MAGENTA" "$NC"; }

ui_stats() {
  local label1="$1" value1="$2" label2="$3" value2="$4" label3="$5" value3="$6"
  printf '\n  %b%s%b %b%s%b   %b%s%b %b%s%b   %b%s%b %b%s%b\n' \
    "$MUTED" "$label1" "$NC" "$CYAN$BOLD" "$value1" "$NC" \
    "$MUTED" "$label2" "$NC" "$GREEN$BOLD" "$value2" "$NC" \
    "$MUTED" "$label3" "$NC" "$YELLOW$BOLD" "$value3" "$NC"
}

ui_empty() { printf '  %b◇%b %b%s%b\n' "$MUTED" "$NC" "$MUTED" "$1" "$NC"; }
ui_note() { printf '\n  %bℹ%b  %b%s%b\n' "$BLUE$BOLD" "$NC" "$BLUE" "$1" "$NC"; }
ui_success() { printf '\n  %b✓%b  %b%s%b\n' "$GREEN$BOLD" "$NC" "$GREEN" "$1" "$NC"; }
ui_danger() { printf '\n  %b!%b  %b%s%b\n' "$RED$BOLD" "$NC" "$RED$BOLD" "$1" "$NC" >&2; }
