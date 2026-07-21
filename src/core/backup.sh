#!/usr/bin/env bash

BACKUP_ROOT="${SERVER_TOOLKIT_BACKUP_ROOT:-/var/backups/server-toolkit}"
BACKUP_SESSION=""

backup_valid_snapshot() {
  [[ "${1:-}" =~ ^[0-9]{8}-[0-9]{6}-[0-9]+$ ]]
}

backup_file() {
  local source="$1"
  [[ -e "$source" || -L "$source" ]] || return 0
  [[ -n "$BACKUP_SESSION" ]] || BACKUP_SESSION="$BACKUP_ROOT/$(date +%Y%m%d-%H%M%S)-$$"
  local destination="$BACKUP_SESSION$source"
  if [[ "$DRY_RUN" -eq 1 ]]; then info "将备份 $source 到 $destination"; return 0; fi
  [[ ! -e "$destination" && ! -L "$destination" ]] || { info "本次会话已经备份：$source"; return 0; }
  mkdir -p "$(dirname "$destination")"
  cp -a "$source" "$destination"
  printf '%s\n' "$source" >>"$BACKUP_SESSION/manifest.txt"
  audit "action=backup source=$source snapshot=$BACKUP_SESSION"
  info "已备份：$source"
}

backup_snapshots() {
  if [[ -d "$BACKUP_ROOT" ]]; then
    find "$BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort -r
  fi
}

backup_manifest() {
  local snapshot="$1"
  backup_valid_snapshot "$snapshot" || return 1
  [[ -r "$BACKUP_ROOT/$snapshot/manifest.txt" ]] || return 1
  cat "$BACKUP_ROOT/$snapshot/manifest.txt"
}

backup_verify() {
  local snapshot="$1" manifest target source checked=0 failed=0
  backup_valid_snapshot "$snapshot" || { warn "备份编号格式无效：$snapshot"; return 1; }
  manifest="$BACKUP_ROOT/$snapshot/manifest.txt"
  [[ -r "$manifest" ]] || { warn "备份清单不存在：$snapshot"; return 1; }
  while IFS= read -r target || [[ -n "$target" ]]; do
    [[ -n "$target" ]] || continue
    checked=$((checked + 1))
    if [[ "$target" != /* || "$target" == *'/../'* || "$target" == */.. ]]; then
      printf '  %b×%b 非法清单路径：%s\n' "$RED" "$NC" "$target"
      failed=$((failed + 1))
      continue
    fi
    source="$BACKUP_ROOT/$snapshot$target"
    if [[ -e "$source" || -L "$source" ]]; then
      printf '  %b✓%b %s\n' "$GREEN" "$NC" "$target"
    else
      printf '  %b×%b 缺少备份内容：%s\n' "$RED" "$NC" "$target"
      failed=$((failed + 1))
    fi
  done <"$manifest"
  (( checked > 0 )) || { warn "备份清单为空：$snapshot"; return 1; }
  (( failed == 0 ))
}

backup_delete() {
  local snapshot="$1" snapshot_dir
  backup_valid_snapshot "$snapshot" || die "备份编号格式无效：$snapshot"
  safe_managed_path "$BACKUP_ROOT" || die "备份根目录不安全：$BACKUP_ROOT"
  snapshot_dir="$BACKUP_ROOT/$snapshot"
  [[ -d "$snapshot_dir" && ! -L "$snapshot_dir" ]] || die "备份不存在或不是安全目录：$snapshot"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    info "将删除配置快照：$snapshot_dir"
    return 0
  fi
  rm -rf -- "$snapshot_dir"
}

backup_restore() {
  local snapshot target source
  snapshot="$1"
  target="$2"
  source="$BACKUP_ROOT/$snapshot$target"
  backup_manifest "$snapshot" | grep -Fxq "$target" || die "目标不在备份清单中：$target"
  [[ -e "$source" || -L "$source" ]] || die "备份文件不存在：$source"
  backup_file "$target"
  if [[ "$DRY_RUN" -eq 1 ]]; then info "将恢复 $source 到 $target"; return 0; fi
  mkdir -p "$(dirname "$target")"
  cp -a "$source" "$target"
  audit "action=restore snapshot=$snapshot target=$target"
  info "已恢复：$target"
}
