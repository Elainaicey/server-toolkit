#!/usr/bin/env bash

services_audit_log() {
  ui_page "项目操作记录" "最近 100 条系统修改审计"
  if [[ -r "$AUDIT_LOG" ]]; then
    tail -n 100 "$AUDIT_LOG"
  else
    ui_empty "尚无操作记录"
  fi
}
