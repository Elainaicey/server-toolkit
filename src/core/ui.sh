#!/usr/bin/env bash

UI_WIDTH=80

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
  printf -v line '%*s' "$count" ''
  printf '%s' "${line// /$character}"
}

ui_rule() {
  printf '%b' "$DIM"
  ui_repeat '─' "$UI_WIDTH"
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
  printf '\n  %bSERVER TOOLKIT%b  %bv%s%b\n' "$BOLD" "$NC" "$CYAN" "$SERVERCTL_VERSION" "$NC"
  printf '  %bDebian / Ubuntu · 安全、清晰、可恢复的 VPS 控制台%b\n' "$DIM" "$NC"
  printf '%b' "$CYAN"
  ui_repeat '━' "$UI_WIDTH"
  printf '%b\n' "$NC"
}

ui_context() {
  printf '%b  %s%b\n' "$DIM" "$1" "$NC"
}

ui_item() {
  local number="$1" title="$2" hint="${3:-}"
  printf '  %b%2s%b  %b%-18s%b' "$CYAN$BOLD" "$number" "$NC" "$BOLD" "$title" "$NC"
  if [[ -n "$hint" ]]; then
    printf ' %b%s%b' "$DIM" "$hint" "$NC"
  fi
  printf '\n'
}

ui_kv() { printf '  %b%-16s%b %s\n' "$DIM" "$1" "$NC" "$2"; }

ui_section() { printf '\n%b▸ %s%b\n' "$CYAN" "$1" "$NC"; }

ui_empty() { printf '  %b— %s%b\n' "$DIM" "$1" "$NC"; }

ui_note() { printf '\n%b  i  %s%b\n' "$BLUE" "$1" "$NC"; }

ui_danger() { printf '\n%b  !  %s%b\n' "$RED$BOLD" "$1" "$NC" >&2; }
