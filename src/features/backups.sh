#!/usr/bin/env bash

backups_list() {
  ui_page "配置备份" "按时间倒序显示快照及文件数量"
  local snapshots=() snapshot count
  mapfile -t snapshots < <(backup_snapshots)
  ((${#snapshots[@]} > 0)) || { ui_empty "还没有配置备份"; return 0; }
  for snapshot in "${snapshots[@]}"; do
    count="$(backup_manifest "$snapshot" 2>/dev/null | grep -c . || true)"
    printf '  %-24s %s files\n' "$snapshot" "$count"
  done
}

backups_inspect() {
  local snapshot; snapshot="$(read_input "备份编号" "")"; [[ -n "$snapshot" ]] || return 0
  ui_page "备份内容" "$snapshot"
  backup_manifest "$snapshot" | nl -ba || { warn "备份不存在或清单无效。"; return 1; }
}

backups_create() {
  local target
  ui_page "创建配置快照" "手动备份一个 /etc 下的现有配置文件"
  target="$(read_input "配置文件完整路径" "/etc/hosts")"
  [[ "$target" == /etc/* && "$target" != *'/../'* && "$target" != */.. ]] || { warn "只允许备份 /etc 下的明确路径。"; return 1; }
  [[ -f "$target" || -L "$target" ]] || { warn "目标不是现有文件：$target"; return 1; }
  confirm "备份 $target？" || return 0
  require_root
  backup_file "$target"
}

backups_restore() {
  local snapshot target
  snapshot="$(read_input "备份编号" "")"; [[ -n "$snapshot" ]] || return 0
  backup_manifest "$snapshot" >/dev/null || { warn "备份不存在或清单无效。"; return 1; }
  printf '\n'; backup_manifest "$snapshot" | nl -ba
  target="$(read_input "要恢复的完整路径" "")"; [[ -n "$target" ]] || return 0
  backup_manifest "$snapshot" | grep -Fxq "$target" || { warn "路径不在该备份清单中。"; return 1; }
  confirm "从 $snapshot 恢复 $target？当前文件会先备份。" || return 0
  require_root; backup_restore "$snapshot" "$target"
}

backups_menu() {
  local choice
  while true; do
    ui_page "备份与恢复" "浏览配置快照并按清单恢复单个文件"
    ui_section "查看" "primary"
    ui_item 1 "列出备份"
    ui_item 3 "查看备份内容"
    ui_section "创建与恢复" "accent"
    ui_item 2 "创建配置快照" "手动备份一个 /etc 配置文件"
    ui_item 4 "恢复一个文件"
    ui_item 0 "返回"
    choice="$(read_input "请选择" "0")"
    case "$choice" in
      1) backups_list ;;
      2) backups_create || true ;;
      3) backups_inspect || true ;;
      4) backups_restore || true ;;
      0) return 0 ;;
      *) warn "未知选项"; continue ;;
    esac
    pause
  done
}
