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

ui_rule() {
  printf '%b' "$MUTED"
  ui_repeat '─' "$UI_WIDTH"
  printf '%b\n' "$NC"
}

ui_page() {
  local title="$1" subtitle="${2:-}"
  ui_clear
  ui_detect_width
  printf '\n%bSERVER TOOLKIT%b  %b/%b  %b%s%b\n' "$MUTED" "$NC" "$MUTED" "$NC" "$BOLD$CYAN" "$title" "$NC"
  if [[ -n "$subtitle" ]]; then
    printf '%b%s%b\n' "$MUTED" "$subtitle" "$NC"
  fi
  printf '%b' "$CYAN"
  ui_repeat '━' "$UI_WIDTH"
  printf '%b\n' "$NC"
}

ui_header() {
  printf '\n%b◆ %s%b\n' "$BOLD$CYAN" "$1" "$NC"
  ui_rule
}

ui_badge() { printf '%b[%s]%b' "${2:-$GREEN}" "$1" "$NC"; }

ui_banner() {
  ui_clear
  ui_detect_width
  printf '\n  %bSERVER TOOLKIT%b  %bv%s%b\n' "$BOLD$WHITE" "$NC" "$CYAN" "$SERVERCTL_VERSION" "$NC"
  printf '  %bDebian / Ubuntu · 安全、清晰、可恢复的 VPS 控制台%b\n' "$MUTED" "$NC"
  printf '%b' "$CYAN"
  ui_repeat '━' "$UI_WIDTH"
  printf '%b\n' "$NC"
}

ui_context() { printf '%b  %s%b\n' "$MUTED" "$1" "$NC"; }

ui_item() {
  local number="$1" title="$2" hint="${3:-}"
  printf '  %b%2s%b  %b' "$CYAN$BOLD" "$number" "$NC" "$WHITE$BOLD"
  ui_pad "$title" 22
  printf '%b' "$NC"
  if [[ -n "$hint" ]]; then printf ' %b%s%b' "$MUTED" "$hint" "$NC"; fi
  printf '\n'
}

ui_kv() {
  local label="$1" value="$2" value_color="${3:-$WHITE}"
  printf '  %b' "$MUTED"
  ui_pad "$label" "$UI_LABEL_WIDTH"
  printf '%b%b%s%b\n' "$NC" "$value_color" "$value" "$NC"
}

ui_status() {
  local label="$1" value="$2" state="${3:-neutral}" color="$WHITE"
  case "$state" in
    good) color="$GREEN" ;;
    warn) color="$YELLOW" ;;
    bad) color="$RED" ;;
  esac
  ui_kv "$label" "$value" "$color"
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
  printf '  %b' "$MUTED"
  ui_pad "$label" "$UI_LABEL_WIDTH"
  printf '%b%b' "$NC" "$color"
  ui_repeat '█' "$filled"
  printf '%b%b' "$NC" "$MUTED"
  ui_repeat '░' "$empty"
  printf '%b  %b%3s%%%b  %s/%s %s\n' "$NC" "$color" "$percent" "$NC" "$current" "$total" "$unit"
}

ui_section() { printf '\n%b▸ %s%b\n' "$CYAN$BOLD" "$1" "$NC"; }
ui_empty() { printf '  %b— %s%b\n' "$MUTED" "$1" "$NC"; }
ui_note() { printf '\n%b  i  %s%b\n' "$BLUE" "$1" "$NC"; }
ui_danger() { printf '\n%b  !  %s%b\n' "$RED$BOLD" "$1" "$NC" >&2; }
