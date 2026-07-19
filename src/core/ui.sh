#!/usr/bin/env bash

ui_clear() { if [[ -t 1 ]] && command_exists clear; then clear; fi; }
ui_rule() { printf '%b--------------------------------------------------------------------------------%b\n' "$DIM" "$NC"; }
ui_header() { printf '\n%b%s%b\n' "$BOLD" "$1" "$NC"; ui_rule; }
ui_badge() { printf '%b[%s]%b' "${2:-$GREEN}" "$1" "$NC"; }

ui_banner() {
  ui_clear
  printf '\n%bServer Toolkit%b  %bv%s%b\n' "$BOLD" "$NC" "$CYAN" "$SERVERCTL_VERSION" "$NC"
  printf '%bDebian / Ubuntu VPS 控制台%b\n' "$DIM" "$NC"
  ui_rule
}

ui_item() {
  local number="$1" title="$2" hint="${3:-}"
  printf '  %b[%s]%b %-22s' "$CYAN" "$number" "$NC" "$title"
  [[ -n "$hint" ]] && printf ' %b%s%b' "$DIM" "$hint" "$NC"
  printf '\n'
}

ui_kv() { printf '  %-16s %s\n' "$1" "$2"; }

ui_section() { printf '\n%b%s%b\n' "$CYAN" "$1" "$NC"; }

ui_empty() { printf '  %b%s%b\n' "$DIM" "$1" "$NC"; }
