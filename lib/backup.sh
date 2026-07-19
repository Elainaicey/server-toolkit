#!/usr/bin/env bash

BACKUP_ROOT="${SERVER_TOOLKIT_BACKUP_ROOT:-/var/backups/server-toolkit}"
BACKUP_SESSION=""

backup_file() {
  local source="$1"
  [[ -e "$source" || -L "$source" ]] || return 0
  if [[ -z "$BACKUP_SESSION" ]]; then
    BACKUP_SESSION="$BACKUP_ROOT/$(date +%Y%m%d-%H%M%S)-$$"
  fi
  local destination="$BACKUP_SESSION$source"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    info "将备份 $source 到 $destination"
    return 0
  fi
  if [[ -e "$destination" || -L "$destination" ]]; then
    info "本次会话已经备份：$source"
    return 0
  fi
  mkdir -p "$(dirname "$destination")"
  cp -a "$source" "$destination"
  printf '%s\n' "$source" >>"$BACKUP_SESSION/manifest.txt"
  info "已备份：$source"
}
