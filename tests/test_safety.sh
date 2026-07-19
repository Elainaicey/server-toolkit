#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd)"
# shellcheck source=../src/core/runtime.sh
. "$ROOT_DIR/src/core/runtime.sh"

[[ "$(read_input "测试输入" "默认值" </dev/null)" == "默认值" ]] || {
  printf 'FAIL: 非交互输入没有正确返回默认值\n' >&2
  exit 1
}

valid_port 22 || { printf 'FAIL: 22 应有效\n' >&2; exit 1; }
valid_port 65535 || { printf 'FAIL: 65535 应有效\n' >&2; exit 1; }
if valid_port 0 || valid_port 65536 || valid_port text; then
  printf 'FAIL: 接受了无效端口\n' >&2
  exit 1
fi

safe_managed_path /opt/server-toolkit || { printf 'FAIL: 正常路径被拒绝\n' >&2; exit 1; }
if safe_managed_path / || safe_managed_path /opt || safe_managed_path /var/../etc; then
  printf 'FAIL: 接受了危险路径\n' >&2
  exit 1
fi

valid_service_name ssh.service || { printf 'FAIL: 正常服务名被拒绝\n' >&2; exit 1; }
if valid_service_name '../ssh' || valid_service_name 'ssh service'; then
  printf 'FAIL: 接受了危险服务名\n' >&2
  exit 1
fi

valid_network_target github.com || { printf 'FAIL: 正常域名被拒绝\n' >&2; exit 1; }
valid_network_target 2001:db8::1 || { printf 'FAIL: 正常 IPv6 被拒绝\n' >&2; exit 1; }
if valid_network_target '../host' || valid_network_target 'host;reboot'; then
  printf 'FAIL: 接受了危险网络目标\n' >&2
  exit 1
fi

printf 'PASS: safety\n'
