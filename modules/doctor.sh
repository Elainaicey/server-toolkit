#!/usr/bin/env bash

DOCTOR_PASS=0
DOCTOR_WARN=0
DOCTOR_FAIL=0

doctor_result() {
  local level="$1"
  local message="$2"
  case "$level" in
    pass) DOCTOR_PASS=$((DOCTOR_PASS + 1)); printf '  %b[通过]%b %s\n' "$GREEN" "$NC" "$message" ;;
    warn) DOCTOR_WARN=$((DOCTOR_WARN + 1)); printf '  %b[提醒]%b %s\n' "$YELLOW" "$NC" "$message" ;;
    fail) DOCTOR_FAIL=$((DOCTOR_FAIL + 1)); printf '  %b[失败]%b %s\n' "$RED" "$NC" "$message" ;;
  esac
}

doctor_check_project() {
  print_section "项目完整性"
  local path
  for path in \
    "$ROOT_DIR/serverctl.sh" \
    "$ROOT_DIR/lib/core.sh" \
    "$ROOT_DIR/lib/catalog.sh" \
    "$ROOT_DIR/catalog/packages.tsv" \
    "$ROOT_DIR/modules/base.sh" \
    "$ROOT_DIR/profiles/minimal.conf"; do
    if [[ -r "$path" ]]; then
      doctor_result pass "$(basename "$path") 可读"
    else
      doctor_result fail "缺少或不可读：$path"
    fi
  done

  local duplicate_ids invalid_lines
  duplicate_ids="$(catalog_rows | awk -F '|' '{ count[$1]++ } END { for (id in count) if (count[id] > 1) print id }')"
  invalid_lines="$(awk -F '|' '!/^#/ && (NF != 5 || $1 !~ /^[a-z0-9][a-z0-9-]*$/) { print NR }' "$CATALOG_FILE")"
  [[ -z "$duplicate_ids" ]] && doctor_result pass "软件目录 ID 无重复" || doctor_result fail "软件目录存在重复 ID：$duplicate_ids"
  [[ -z "$invalid_lines" ]] && doctor_result pass "软件目录格式有效" || doctor_result fail "软件目录格式错误，行号：$invalid_lines"
}

doctor_check_system() {
  print_section "系统环境"
  case "$OS_FAMILY" in
    debian|rhel) doctor_result pass "支持的系统：$OS_ID $OS_VERSION_ID ($ARCH)" ;;
    *) doctor_result fail "不支持的系统：$OS_ID $OS_VERSION_ID" ;;
  esac
  command_exists "$PM" && doctor_result pass "包管理器可用：$PM" || doctor_result fail "包管理器不可用：$PM"
  command_exists curl && doctor_result pass "curl 可用" || doctor_result warn "缺少 curl，部分官方仓库安装会失败"
  command_exists tar && doctor_result pass "tar 可用" || doctor_result warn "缺少 tar，远程安装器无法解包"
  [[ "$DNS_OK" -eq 1 ]] && doctor_result pass "DNS 解析正常" || doctor_result warn "DNS 解析异常"
  [[ "$GITHUB_OK" -eq 1 ]] && doctor_result pass "GitHub 连通" || doctor_result warn "GitHub 暂不可达，外部仓库安装可能失败"
  [[ -z "$APT_ISSUES" ]] && doctor_result pass "系统包状态正常" || doctor_result fail "检测到 dpkg/apt 未完成状态"

  local available_mb
  available_mb="$(df -Pm / 2>/dev/null | awk 'NR == 2 { print $4 }')"
  if [[ "$available_mb" =~ ^[0-9]+$ ]] && (( available_mb < 512 )); then
    doctor_result warn "根分区可用空间仅 ${available_mb} MB"
  else
    doctor_result pass "根分区可用空间 ${available_mb:-未知} MB"
  fi
  if [[ "$MEM_TOTAL_MB" =~ ^[0-9]+$ ]] && (( MEM_TOTAL_MB < 512 )); then
    doctor_result warn "内存仅 ${MEM_TOTAL_MB} MB，安装数据库或编译工具前建议创建 Swap"
  else
    doctor_result pass "内存 ${MEM_TOTAL_MB:-未知} MB"
  fi
}

run_doctor() {
  DOCTOR_PASS=0
  DOCTOR_WARN=0
  DOCTOR_FAIL=0
  detect_system refresh
  print_title "Server Toolkit 自检"
  doctor_check_project
  doctor_check_system
  printf '\n'
  ui_panel_start "自检结果"
  ui_panel_line "通过 $DOCTOR_PASS · 提醒 $DOCTOR_WARN · 失败 $DOCTOR_FAIL"
  if (( DOCTOR_FAIL > 0 )); then
    ui_panel_line "存在需要处理的问题；可结合 serverctl repair 继续诊断。"
  elif (( DOCTOR_WARN > 0 )); then
    ui_panel_line "核心检查通过，提醒项不会阻止大多数功能运行。"
  else
    ui_panel_line "所有检查均通过。"
  fi
  ui_panel_end
  return 0
}
