#!/usr/bin/env bash

system_overview() {
  platform_detect
  ui_header "系统概览"
  ui_kv "系统" "$OS_NAME"
  ui_kv "架构" "$ARCH"
  ui_kv "虚拟化" "$VIRTUALIZATION"
  ui_kv "CPU" "$CPU_CORES 核"
  ui_kv "内存" "$MEMORY_MB MB"
  ui_kv "Swap" "$SWAP_MB MB"
  ui_kv "根分区" "${ROOT_USAGE:-未知}"
  ui_kv "主机名" "$(hostname 2>/dev/null || printf '未知')"
  ui_kv "时区" "$(timedatectl show -p Timezone --value 2>/dev/null || date +%Z)"
  ui_kv "SSH 端口" "$(detect_ssh_port)"
  if command_exists ufw; then
    ui_kv "防火墙" "$(ufw status 2>/dev/null | head -n1)"
  else
    ui_kv "防火墙" "未安装"
  fi
}

doctor_result() {
  local level="$1" message="$2"
  case "$level" in
    pass) printf '  %b✓%b %s\n' "$GREEN" "$NC" "$message" ;;
    warn) printf '  %b!%b %s\n' "$YELLOW" "$NC" "$message" ;;
    fail) printf '  %b×%b %s\n' "$RED" "$NC" "$message" ;;
  esac
}

system_doctor() {
  platform_detect
  ui_header "环境检查"
  doctor_result pass "$OS_NAME ($ARCH)"
  if command_exists apt-get; then doctor_result pass "APT 可用"; else doctor_result fail "缺少 apt-get"; fi
  if command_exists dpkg-query; then doctor_result pass "dpkg 可用"; else doctor_result fail "缺少 dpkg-query"; fi

  local audit
  audit="$(dpkg --audit 2>/dev/null || true)"
  if [[ -z "$audit" ]]; then doctor_result pass "软件包状态正常"; else doctor_result fail "存在未完成的软件包配置"; fi

  local free_mb
  free_mb="$(df -Pm / 2>/dev/null | awk 'NR == 2 {print $4}')"
  if [[ "$free_mb" =~ ^[0-9]+$ ]] && (( free_mb >= 512 )); then
    doctor_result pass "根分区可用 ${free_mb} MB"
  else
    doctor_result warn "根分区剩余空间不足 512 MB"
  fi

  if getent hosts deb.debian.org >/dev/null 2>&1; then
    doctor_result pass "DNS 解析正常"
  else
    doctor_result fail "DNS 解析失败"
  fi
  if command_exists curl; then
    curl -fsI --connect-timeout 2 --max-time 5 https://github.com >/dev/null 2>&1 \
      && doctor_result pass "GitHub 可访问" \
      || doctor_result warn "GitHub 当前不可访问"
  else
    doctor_result warn "未安装 curl，跳过 HTTPS 连通检查"
  fi

  if [[ "$MEMORY_MB" =~ ^[0-9]+$ ]] && (( MEMORY_MB < 512 )) && [[ "$SWAP_MB" == "0" ]]; then
    doctor_result warn "内存小于 512 MB 且没有 Swap"
  else
    doctor_result pass "内存与 Swap 状态可用"
  fi
}

system_set_hostname() {
  local current name
  current="$(hostname -s 2>/dev/null || hostname)"
  name="$(read_input "新主机名" "$current")"
  [[ "$name" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$ ]] || { warn "主机名格式无效。"; return 1; }
  [[ "$name" != "$current" ]] || { info "主机名未变化。"; return 0; }
  confirm "将主机名从 $current 修改为 $name？" || { warn "已取消。"; return 0; }
  require_root
  backup_file /etc/hostname
  backup_file /etc/hosts
  run hostnamectl set-hostname "$name"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    info "将更新 /etc/hosts 中的 127.0.1.1 记录。"
    return 0
  fi
  local temporary
  temporary="$(mktemp)"
  awk -v name="$name" '
    BEGIN { changed=0 }
    $1 == "127.0.1.1" { print "127.0.1.1 " name; changed=1; next }
    { print }
    END { if (!changed) print "127.0.1.1 " name }
  ' /etc/hosts >"$temporary"
  install -m 0644 "$temporary" /etc/hosts
  rm -f "$temporary"
}

system_set_timezone() {
  local current timezone
  current="$(timedatectl show -p Timezone --value 2>/dev/null || printf 'Etc/UTC')"
  timezone="$(read_input "时区" "$current")"
  [[ -f "/usr/share/zoneinfo/$timezone" ]] || { warn "不存在的时区：$timezone"; return 1; }
  [[ "$timezone" != "$current" ]] || { info "时区未变化。"; return 0; }
  confirm "将时区修改为 $timezone？" || { warn "已取消。"; return 0; }
  require_root
  backup_file /etc/timezone
  run timedatectl set-timezone "$timezone"
}

system_create_swap() {
  if swapon --show --noheadings 2>/dev/null | grep -q .; then
    warn "系统已经启用 Swap，本工具不会重复创建。"
    return 0
  fi
  [[ ! -e /swapfile ]] || { warn "/swapfile 已存在，为避免覆盖已停止。"; return 1; }
  local size_mb
  size_mb="$(read_input "Swap 大小（MB）" "1024")"
  [[ "$size_mb" =~ ^[0-9]+$ ]] && (( size_mb >= 128 && size_mb <= 32768 )) || {
    warn "Swap 大小必须在 128 到 32768 MB 之间。"
    return 1
  }
  confirm "创建 ${size_mb} MB 的 /swapfile？" || { warn "已取消。"; return 0; }
  require_root
  backup_file /etc/fstab
  if command_exists fallocate; then
    if ! run fallocate -l "${size_mb}M" /swapfile; then
      run dd if=/dev/zero of=/swapfile bs=1M count="$size_mb" status=progress
    fi
  else
    run dd if=/dev/zero of=/swapfile bs=1M count="$size_mb" status=progress
  fi
  run chmod 600 /swapfile
  run mkswap /swapfile
  run swapon /swapfile
  if [[ "$DRY_RUN" -eq 1 ]]; then
    info "将向 /etc/fstab 添加 /swapfile。"
  else
    printf '/swapfile none swap sw 0 0\n' >>/etc/fstab
  fi
}
