#!/usr/bin/env bash

clear_screen() {
  [[ -t 1 ]] && command_exists clear && clear || true
}

ui_cols() {
  local cols="80"
  if command_exists tput; then
    cols="$(tput cols 2>/dev/null || printf '80')"
  fi
  [[ "$cols" =~ ^[0-9]+$ ]] || cols=80
  (( cols < 72 )) && cols=72
  (( cols > 110 )) && cols=110
  printf '%s' "$cols"
}

ui_repeat() {
  local char="${1:-─}"
  local count="${2:-1}"
  local i
  for ((i = 0; i < count; i++)); do
    printf '%s' "$char"
  done
}

ui_rule() {
  local cols
  cols="$(ui_cols)"
  printf '%b' "$DIM"
  ui_repeat "─" "$cols"
  printf '%b\n' "$NC"
}

ui_short() {
  local value="$1"
  local max="${2:-28}"
  if ((${#value} > max)); then
    printf '%s...' "${value:0:max-3}"
  else
    printf '%s' "$value"
  fi
}

ui_panel_start() {
  local title="$1"
  local cols fill
  cols="$(ui_cols)"
  fill=$((cols - ${#title} - 5))
  (( fill < 12 )) && fill=12
  printf '%b╭─ %s %b' "$CYAN" "$title" "$NC"
  ui_repeat "─" "$fill"
  printf '\n'
}

ui_panel_line() {
  printf '%b│%b %s\n' "$CYAN" "$NC" "$*"
}

ui_panel_gap() {
  printf '%b│%b\n' "$CYAN" "$NC"
}

ui_panel_end() {
  local cols
  cols="$(ui_cols)"
  printf '%b╰%b' "$CYAN" "$NC"
  ui_repeat "─" "$((cols - 1))"
  printf '\n'
}

ui_badge() {
  local text="$1"
  local color="${2:-$GREEN}"
  printf '%b[%s]%b' "$color" "$text" "$NC"
}

print_title() {
  local title="$1"
  printf '\n'
  ui_panel_start "$title"
  ui_panel_end
  printf '\n'
}

print_section() {
  local title="$1"
  printf '\n%b▸ %s%b\n' "$CYAN" "$title" "$NC"
}

print_kv() {
  local key="$1"
  local value="$2"
  printf '  %b%s%b  %s\n' "$DIM" "$key" "$NC" "$value"
}

print_main_banner() {
  local version="$1"
  local cols
  cols="$(ui_cols)"
  printf '\n'
  printf '%b╭─%b %bServer Toolkit%b %bv%s%b ' "$CYAN" "$NC" "$BOLD" "$NC" "$CYAN" "$version" "$NC"
  ui_repeat "─" "$((cols - 29))"
  printf '\n'
  printf '%b│%b  VPS 初始化 · 运维 · 修复 · 环境管理\n' "$CYAN" "$NC"
  printf '%b╰%b' "$CYAN" "$NC"
  ui_repeat "─" "$((cols - 1))"
  printf '\n\n'
}

print_menu_hint() {
  ui_panel_start "提示"
  ui_panel_line "$(printf '%b建议%b  先看「系统总览与建议」，再进入具体模块。' "$YELLOW" "$NC")"
  ui_panel_line "危险操作会单独确认；卸载默认保留日志和备份。"
  ui_panel_end
  printf '\n'
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
