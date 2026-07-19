#!/usr/bin/env bash

ui_clear() {
  if [[ -t 1 ]] && command_exists clear; then
    clear
  fi
}

ui_rule() {
  printf '%b------------------------------------------------------------------------%b\n' "$DIM" "$NC"
}

ui_header() {
  local title="$1"
  printf '\n%b%s%b\n' "$BOLD" "$title" "$NC"
  ui_rule
}

ui_banner() {
  ui_clear
  printf '\n%bServer Toolkit%b  %bv%s%b\n' "$BOLD" "$NC" "$CYAN" "$SERVERCTL_VERSION" "$NC"
  printf '%b简洁、可审计的 Debian / Ubuntu VPS 工具%b\n' "$DIM" "$NC"
  ui_rule
}

ui_item() {
  local number="$1"
  local title="$2"
  local hint="${3:-}"
  printf '  %b[%s]%b %s' "$CYAN" "$number" "$NC" "$title"
  [[ -n "$hint" ]] && printf '  %b%s%b' "$DIM" "$hint" "$NC"
  printf '\n'
}

ui_kv() {
  printf '  %-14s %s\n' "$1" "$2"
}
