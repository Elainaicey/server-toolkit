#!/usr/bin/env bash

OS_ID=""
OS_VERSION_ID=""
OS_FAMILY=""
OS_CODENAME=""
PM=""
ARCH=""
VIRT=""
CPU_CORES=""
MEM_TOTAL_MB=""
SWAP_TOTAL_MB=""
ROOT_USAGE=""
HAS_IPV4=0
HAS_IPV6=0
DNS_OK=0
GITHUB_OK=0
APT_ISSUES=""
SSH_SERVICE=""
SSH_PORT="22"
FIREWALL_STATE=""
PORT_80=""
PORT_443=""

detect_system() {
  [[ -f /etc/os-release ]] || die "无法检测系统：缺少 /etc/os-release"
  # shellcheck source=/dev/null
  . /etc/os-release
  OS_ID="${ID:-unknown}"
  OS_VERSION_ID="${VERSION_ID:-unknown}"
  OS_CODENAME="${VERSION_CODENAME:-${UBUNTU_CODENAME:-}}"
  ARCH="$(dpkg --print-architecture 2>/dev/null || uname -m)"
  CPU_CORES="$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo unknown)"
  MEM_TOTAL_MB="$(awk '/MemTotal/ {printf "%.0f", $2/1024}' /proc/meminfo 2>/dev/null || echo unknown)"
  SWAP_TOTAL_MB="$(awk '/SwapTotal/ {printf "%.0f", $2/1024}' /proc/meminfo 2>/dev/null || echo 0)"
  ROOT_USAGE="$(df -h / 2>/dev/null | awk 'NR==2 {print $3 "/" $2 " (" $5 ")"}')"
  VIRT="$(systemd-detect-virt 2>/dev/null || echo unknown)"

  case "$OS_ID" in
    debian|ubuntu) OS_FAMILY="debian"; PM="apt-get" ;;
    rhel|centos|rocky|almalinux|fedora) OS_FAMILY="rhel"; command_exists dnf && PM="dnf" || PM="yum" ;;
    *)
      if [[ "${ID_LIKE:-}" == *debian* ]]; then OS_FAMILY="debian"; PM="apt-get";
      elif [[ "${ID_LIKE:-}" == *rhel* || "${ID_LIKE:-}" == *fedora* ]]; then OS_FAMILY="rhel"; command_exists dnf && PM="dnf" || PM="yum";
      else die "暂不支持的系统：$OS_ID $OS_VERSION_ID"; fi
      ;;
  esac

  ip -4 route get 1.1.1.1 >/dev/null 2>&1 && HAS_IPV4=1 || HAS_IPV4=0
  ip -6 route get 2606:4700:4700::1111 >/dev/null 2>&1 && HAS_IPV6=1 || HAS_IPV6=0
  getent hosts github.com >/dev/null 2>&1 && DNS_OK=1 || DNS_OK=0
  if command_exists curl; then
    curl -fsI --connect-timeout 5 --max-time 10 https://github.com >/dev/null 2>&1 && GITHUB_OK=1 || GITHUB_OK=0
  fi

  if [[ "$OS_FAMILY" == "debian" ]]; then
    APT_ISSUES="$(dpkg --audit 2>/dev/null | sed -n '1,8p' || true)"
  fi

  if systemctl list-unit-files 2>/dev/null | grep -q '^sshd\.service'; then SSH_SERVICE="sshd";
  elif systemctl list-unit-files 2>/dev/null | grep -q '^ssh\.service'; then SSH_SERVICE="ssh";
  else SSH_SERVICE="sshd"; fi
  if command_exists sshd; then
    SSH_PORT="$(sshd -T 2>/dev/null | awk '/^port / {print $2; exit}' || echo 22)"
  fi
  FIREWALL_STATE="$(detect_firewall_state)"
  PORT_80="$(detect_port_owner 80)"
  PORT_443="$(detect_port_owner 443)"
}

detect_port_owner() {
  local port="$1"
  local line=""
  local proto=""
  local process=""
  if command_exists ss; then
    line="$(ss -H -ltnp "sport = :${port}" 2>/dev/null | head -n1 || true)"
    [[ -z "$line" ]] && line="$(ss -H -lunp "sport = :${port}" 2>/dev/null | head -n1 || true)"
    [[ -z "$line" ]] && return 0
    proto="$(awk '{print $1}' <<< "$line")"
    process="$(sed -n 's/.*users:((\"\([^\"]*\)\".*/\1/p' <<< "$line")"
    if [[ -n "$process" ]]; then
      printf '%s(%s)' "$process" "${proto:-tcp}"
    else
      printf '已占用'
    fi
  fi
}

detect_firewall_state() {
  if command_exists ufw; then
    ufw status 2>/dev/null | head -n1
  elif command_exists firewall-cmd; then
    firewall-cmd --state 2>/dev/null || true
  else
    printf '未安装'
  fi
}

print_detection_summary() {
  detect_system
  print_title "系统检测"
  cat <<SUMMARY
系统：        ${OS_ID} ${OS_VERSION_ID}
架构：        ${ARCH}
虚拟化：      ${VIRT}
CPU 核心：    ${CPU_CORES}
内存：        ${MEM_TOTAL_MB} MB
Swap：        ${SWAP_TOTAL_MB} MB
根分区：      ${ROOT_USAGE:-未知}
IPv4：        $([[ $HAS_IPV4 -eq 1 ]] && echo 可用 || echo 不可用/未知)
IPv6：        $([[ $HAS_IPV6 -eq 1 ]] && echo 可用 || echo 不可用/未知)
DNS：         $([[ $DNS_OK -eq 1 ]] && echo 正常 || echo 异常/未知)
GitHub：      $([[ $GITHUB_OK -eq 1 ]] && echo 可访问 || echo 不可访问/未知)
包管理器：    ${PM}
APT 状态：    $([[ -n "$APT_ISSUES" ]] && echo "有异常" || echo "正常")
SSH 服务：    ${SSH_SERVICE}
SSH 端口：    ${SSH_PORT}
防火墙：      ${FIREWALL_STATE}
80 端口：     ${PORT_80:-空闲/未知}
443 端口：    ${PORT_443:-空闲/未知}
SUMMARY
  if [[ -n "$APT_ISSUES" ]]; then
    printf '\nAPT/dpkg 异常：\n%s\n' "$APT_ISSUES"
  fi
  print_detection_advice
}

print_detection_advice() {
  print_section "建议"
  local has_advice=0
  if [[ -n "$APT_ISSUES" ]]; then
    printf '  - 检测到 APT/dpkg 异常，建议进入「系统修复与回滚」处理后再安装软件。\n'
    has_advice=1
  fi
  if [[ "$HAS_IPV4" -eq 0 && "$HAS_IPV6" -eq 1 ]]; then
    printf '  - 当前看起来像 IPv6-only 环境，安装 Docker/外部源时要注意源站 IPv6 连通性。\n'
    has_advice=1
  fi
  if [[ "$GITHUB_OK" -eq 0 ]]; then
    printf '  - GitHub 连通性异常，安装 oh-my-zsh、Rust、部分官方仓库可能失败。\n'
    has_advice=1
  fi
  if [[ -n "$PORT_80" || -n "$PORT_443" ]]; then
    printf '  - 80/443 端口已有监听服务，安装 Caddy/Nginx 前建议确认是否冲突。\n'
    has_advice=1
  fi
  if [[ "$FIREWALL_STATE" == "未安装" || "$FIREWALL_STATE" == "not installed" ]]; then
    printf '  - 防火墙未启用。如是公网 VPS，建议至少放行 SSH 后启用基础防火墙。\n'
    has_advice=1
  fi
  if [[ "$has_advice" -eq 0 ]]; then
    printf '  - 暂未发现明显风险，可以按需进入各模块操作。\n'
  fi
}

generate_report() {
  detect_system
  local report="/root/server-report.txt"
  [[ "$DRY_RUN" -eq 1 ]] && report="/tmp/server-report.txt"
  {
    printf 'Server Toolkit 系统报告\n'
    printf '生成时间：%s\n\n' "$(date -Is)"
    print_detection_summary
    printf '\n监听端口：\n'
    ss -tulpn 2>/dev/null || true
    printf '\n运行中的服务：\n'
    systemctl --type=service --state=running --no-pager 2>/dev/null | sed -n '1,80p' || true
    printf '\nDocker:\n'
    docker version 2>/dev/null || true
  } > "$report"
  log_info "报告已生成：$report"
}
