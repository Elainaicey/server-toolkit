#!/usr/bin/env bash

catalog_state_badge() {
  case "$1" in
    absent) ui_badge "未安装" "$MUTED" ;;
    unavailable) ui_badge "仓库不可用" "$RED" ;;
    update) ui_badge "可更新" "$YELLOW" ;;
    current) ui_badge "已是最新" "$GREEN" ;;
    managed) ui_badge "已安装" "$GREEN" ;;
    damaged) ui_badge "完整性异常" "$RED" ;;
    *) ui_badge "未知" "$MUTED" ;;
  esac
}

catalog_statistics() {
  local record id _category _name _description _packages handler package total=0 installed=0 updates=0
  local -A upgradable=()
  if command_exists apt; then
    while IFS= read -r package; do
      [[ -n "$package" ]] && upgradable["$package"]=1
    done < <(apt list --upgradable 2>/dev/null | sed '1d;s#/.*##')
  fi
  while IFS= read -r record; do
    total=$((total + 1))
    if catalog_installed "$record"; then
      installed=$((installed + 1))
      IFS='|' read -r id _category _name _description _packages handler <<<"$record"
      if [[ "$handler" == "official_release" ]] && software_release_managed "$id"; then
        continue
      fi
      package="$(catalog_primary_package "$record")"
      [[ -n "${upgradable[$package]:-}" ]] && updates=$((updates + 1))
    fi
  done < <(catalog_rows)
  printf '%s|%s|%s' "$total" "$installed" "$updates"
}

catalog_print_record() {
  local record="$1" id _category name description _packages _handler state installed candidate
  IFS='|' read -r id _category name description _packages _handler <<<"$record"
  installed="$(catalog_installed_version "$record")"
  candidate="$(catalog_candidate_version "$record")"
  state="$(catalog_state "$record" "$candidate")"
  printf '  %b›%b %b' "$MAGENTA" "$NC" "$CYAN$BOLD"
  ui_pad "$id" 20
  printf '%b%b' "$NC" "$BLUE$BOLD"
  ui_pad "$name" 22
  printf '%b\n' "$(catalog_state_badge "$state")"
  printf '    %b%s%b\n' "$MUTED" "$description" "$NC"
  if [[ "$state" == "update" ]]; then
    printf '    %b版本%b  %b%s%b %b→%b %b%s%b\n' "$BLUE" "$NC" "$WHITE" "$installed" "$NC" "$MAGENTA" "$NC" "$YELLOW" "$candidate" "$NC"
  elif [[ "$state" == "current" ]]; then
    printf '    %b版本%b  %b%s%b\n' "$BLUE" "$NC" "$GREEN" "$installed" "$NC"
  elif [[ "$state" == "managed" ]]; then
    printf '    %b当前版本%b  %b%s%b  %b· 可检查官方更新%b\n' "$BLUE" "$NC" "$GREEN" "$installed" "$NC" "$MUTED" "$NC"
  elif [[ "$state" == "unavailable" ]]; then
    printf '    %b可用性%b  %b当前系统软件源未提供此软件包%b\n' "$BLUE" "$NC" "$YELLOW" "$NC"
  else
    printf '    %b仓库版本%b  %b%s%b\n' "$BLUE" "$NC" "$WHITE" "$candidate" "$NC"
  fi
}

catalog_print() {
  local query="${1:-}" record category last_category="" count=0
  while IFS= read -r record; do
    IFS='|' read -r _ category _ <<<"$record"
    if [[ "$category" != "$last_category" ]]; then
      [[ -z "$last_category" ]] || printf '\n'
      ui_section "$category" "accent"
      last_category="$category"
    fi
    catalog_print_record "$record"
    count=$((count + 1))
  done < <(catalog_rows "$query")
  (( count > 0 )) || { warn "没有找到与 '$query' 匹配的软件。"; return 1; }
}

catalog_print_category() {
  local category="$1" record count=0
  while IFS= read -r record; do
    catalog_print_record "$record"
    count=$((count + 1))
  done < <(catalog_category_rows "$category")
  (( count > 0 )) || { warn "分类 '$category' 中没有软件。"; return 1; }
}
