#!/usr/bin/env bash

clear_screen() {
  [[ -t 1 ]] && command_exists clear && clear || true
}

print_title() {
  local title="$1"
  printf '\n┌─ %s\n' "$title"
  printf '└────────────────────────────────────────────────────\n\n'
}

print_section() {
  local title="$1"
  printf '\n[%s]\n' "$title"
}

print_kv() {
  local key="$1"
  local value="$2"
  printf '  %-16s %s\n' "$key" "$value"
}

print_main_banner() {
  local version="$1"
  printf '\n'
  printf '╔══════════════════════════════════════════════════════╗\n'
  printf '║              Server Toolkit v%-22s ║\n' "$version"
  printf '║        VPS 初始化 / 运维 / 修复 / 环境管理          ║\n'
  printf '╚══════════════════════════════════════════════════════╝\n'
}

print_menu_hint() {
  printf '\n提示：先看「系统总览」，再按需要进入模块。危险操作会单独确认。\n\n'
}

read_from_tty() {
  local prompt="$1"
  local answer=""
  if [[ -t 0 ]]; then
    read -r -p "$prompt" answer || true
  elif { exec 3</dev/tty; } 2>/dev/null; then
    read -r -p "$prompt" answer <&3 || true
    exec 3<&-
  else
    read -r -p "$prompt" answer || true
  fi
  printf '%s' "$answer"
}

ask_yes_no() {
  local question="$1"
  local default_answer="${2:-Y}"
  local answer=""
  if [[ "$ASSUME_YES" -eq 1 ]]; then
    [[ "$default_answer" =~ ^[Yy]$ ]]
    return $?
  fi
  local prompt="[Y/n]"
  [[ "$default_answer" =~ ^[Nn]$ ]] && prompt="[y/N]"
  answer="$(read_from_tty "${question} ${prompt}: ")"
  answer="${answer:-$default_answer}"
  case "$answer" in
    y|Y|yes|YES|Yes) return 0 ;;
    *) return 1 ;;
  esac
}

ask_input() {
  local question="$1"
  local default_value="${2:-}"
  local answer=""
  if [[ -n "$default_value" ]]; then
    answer="$(read_from_tty "${question} [${default_value}]: ")"
    printf '%s' "${answer:-$default_value}"
  else
    answer="$(read_from_tty "${question}: ")"
    printf '%s' "$answer"
  fi
}

ask_choice() {
  local question="$1"
  local default_value="$2"
  local allowed="$3"
  local answer=""
  while true; do
    answer="$(ask_input "$question" "$default_value")"
    if [[ " ${allowed} " == *" ${answer} "* ]]; then
      printf '%s' "$answer"
      return 0
    fi
    log_warn "允许的值：${allowed}" >&2
  done
}

pause() {
  [[ "$ASSUME_YES" -eq 1 ]] && return 0
  read_from_tty "按 Enter 继续..." >/dev/null
}

choose_numbers() {
  local prompt="$1"
  local answer=""
  answer="$(read_from_tty "${prompt}: ")"
  answer="${answer// /}"
  printf '%s' "$answer"
}
