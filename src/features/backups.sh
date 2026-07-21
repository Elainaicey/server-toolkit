#!/usr/bin/env bash

backups_list() {
  ui_page "配置备份" "按时间倒序显示快照、文件数量与磁盘占用"
  local snapshots=() snapshot count size
  mapfile -t snapshots < <(backup_snapshots)
  ((${#snapshots[@]} > 0)) || { ui_empty "还没有配置备份"; return 0; }
  for snapshot in "${snapshots[@]}"; do
    count="$(backup_manifest "$snapshot" 2>/dev/null | grep -c . || true)"
    size="$(du -sh "$BACKUP_ROOT/$snapshot" 2>/dev/null | awk '{print $1}' || printf '未知')"
    printf '  %b%s%b  %b%3s 个文件%b  %b%s%b\n' "$CYAN" "$snapshot" "$NC" "$WHITE" "$count" "$NC" "$MUTED" "$size" "$NC"
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

backups_verify() {
  local snapshot
  snapshot="$(read_input "备份编号" "")"; [[ -n "$snapshot" ]] || return 0
  ui_page "校验配置快照" "$snapshot · 检查清单格式与备份文件完整性"
  if backup_verify "$snapshot"; then
    ui_success "快照结构完整，可以用于恢复。"
  else
    ui_danger "快照校验失败，请勿使用它覆盖当前配置。"
    return 1
  fi
}

backups_compare() {
  local snapshot target source
  snapshot="$(read_input "备份编号" "")"; [[ -n "$snapshot" ]] || return 0
  backup_manifest "$snapshot" >/dev/null || { warn "备份不存在或清单无效。"; return 1; }
  printf '\n'; backup_manifest "$snapshot" | nl -ba
  target="$(read_input "要比较的完整路径" "")"; [[ -n "$target" ]] || return 0
  backup_manifest "$snapshot" | grep -Fxq "$target" || { warn "路径不在该备份清单中。"; return 1; }
  source="$BACKUP_ROOT/$snapshot$target"
  ui_page "比较配置" "$snapshot · $target"
  [[ -e "$source" || -L "$source" ]] || { warn "备份内容不存在。"; return 1; }
  if [[ ! -e "$target" && ! -L "$target" ]]; then
    ui_status "当前文件" "不存在" "warn"
    ui_status "备份文件" "可用" "good"
    return 0
  fi
  if cmp -s -- "$source" "$target"; then
    ui_success "当前文件与备份内容一致。"
  else
    ui_status "比较结果" "内容已发生变化" "warn"
    ui_section "差异（最多 120 行）" "accent"
    diff -u --label "备份/$snapshot$target" --label "当前$target" "$source" "$target" 2>/dev/null | sed -n '1,120p' || true
  fi
}

backups_delete() {
  local snapshot size count
  snapshot="$(read_input "备份编号" "")"; [[ -n "$snapshot" ]] || return 0
  backup_manifest "$snapshot" >/dev/null || { warn "备份不存在或清单无效。"; return 1; }
  size="$(du -sh "$BACKUP_ROOT/$snapshot" 2>/dev/null | awk '{print $1}' || printf '未知')"
  count="$(backup_manifest "$snapshot" | grep -c . || true)"
  ui_page "删除配置快照" "$snapshot"
  ui_panel_begin "删除目标"
  ui_panel_kv "快照" "$snapshot" "$YELLOW"
  ui_panel_kv "文件" "$count 个"
  ui_panel_kv "占用" "$size"
  ui_panel_end
  ui_danger "删除后无法通过 Server Toolkit 恢复此快照。"
  confirm "确认永久删除快照 $snapshot？" || return 0
  require_root
  backup_delete "$snapshot"
  audit "action=backup-delete snapshot=$snapshot"
  [[ "$DRY_RUN" -eq 1 ]] || ui_success "配置快照已删除。"
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
    ui_section "查看与验证" "primary"
    ui_item 1 "列出备份"
    ui_item 2 "查看备份内容"
    ui_item 3 "校验备份完整性" "检查清单和所有备份文件"
    ui_item 4 "与当前配置比较" "恢复前查看文件差异"
    ui_section "创建与恢复" "accent"
    ui_item 5 "创建配置快照" "手动备份一个 /etc 配置文件"
    ui_item 6 "恢复一个文件"
    ui_item 7 "删除一个快照" "只删除明确选择的项目快照"
    ui_item 0 "返回"
    choice="$(read_input "请选择" "0")"
    case "$choice" in
      1) backups_list ;;
      2) backups_inspect || true ;;
      3) backups_verify || true ;;
      4) backups_compare || true ;;
      5) backups_create || true ;;
      6) backups_restore || true ;;
      7) backups_delete || true ;;
      0) return 0 ;;
      *) warn "未知选项"; continue ;;
    esac
    pause
  done
}
