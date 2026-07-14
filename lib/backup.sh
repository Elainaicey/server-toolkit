#!/usr/bin/env bash

backup_file() {
  local src="$1"
  [[ -e "$src" ]] || return 0
  if [[ "$DRY_RUN" -eq 1 ]]; then
    log_info "[DRY-RUN] 备份 $src -> ${BACKUP_DIR}${src}"
    return 0
  fi
  local dst="${BACKUP_DIR}${src}"
  mkdir -p "$(dirname "$dst")"
  cp -a "$src" "$dst"
  printf '%s\n' "$src" >> "${BACKUP_DIR}/manifest.txt"
  log_info "已备份：$src"
}

restore_file_from_backup() {
  local backup="$1"
  local src="$2"
  local source_path="${backup}${src}"
  [[ -e "$source_path" ]] || die "未找到备份项：$source_path"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    log_info "[DRY-RUN] 恢复 $source_path -> $src"
    return 0
  fi
  cp -a "$source_path" "$src"
  log_info "已恢复：$src"
}

rollback_menu() {
  print_title "回滚备份"
  [[ -d "$BACKUP_ROOT" ]] || { log_warn "没有备份目录：$BACKUP_ROOT"; pause; return 0; }
  local backups=()
  mapfile -t backups < <(find "$BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d | sort -r)
  ((${#backups[@]})) || { log_warn "未找到可用备份。"; pause; return 0; }

  local i=1
  for b in "${backups[@]}"; do
    printf '%d) %s\n' "$i" "$(basename "$b")"
    i=$((i + 1))
  done
  local choice
  choice="$(ask_input "请选择备份" "1")"
  [[ "$choice" =~ ^[0-9]+$ ]] || { log_warn "选择无效"; pause; return 0; }
  local selected="${backups[$((choice - 1))]:-}"
  [[ -n "$selected" ]] || { log_warn "选择无效"; pause; return 0; }

  if [[ ! -f "$selected/manifest.txt" ]]; then
    log_warn "该备份没有 manifest：$selected"
    pause
    return 0
  fi
  nl -ba "$selected/manifest.txt"
  local line
  line="$(ask_input "恢复哪一项？输入 all 恢复全部" "all")"
  if [[ "$line" == "all" ]]; then
    while IFS= read -r item; do
      restore_file_from_backup "$selected" "$item"
    done < "$selected/manifest.txt"
  elif [[ "$line" =~ ^[0-9]+$ ]]; then
    local item
    item="$(sed -n "${line}p" "$selected/manifest.txt")"
    [[ -n "$item" ]] && restore_file_from_backup "$selected" "$item"
  else
    log_warn "输入无效。"
  fi
  pause
}
