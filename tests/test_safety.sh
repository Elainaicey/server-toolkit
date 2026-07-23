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

sanitized_text="$(terminal_safe_text $'safe\e[31m\r\ntext')"
if [[ "$sanitized_text" == *[[:cntrl:]]* || "$sanitized_text" != safe\ \[31m*text ]]; then
  printf 'FAIL: 终端控制字符没有被清理\n' >&2
  exit 1
fi

valid_port 22 || { printf 'FAIL: 22 应有效\n' >&2; exit 1; }
valid_port 65535 || { printf 'FAIL: 65535 应有效\n' >&2; exit 1; }
if valid_port 0 || valid_port 65536 || valid_port text; then
  printf 'FAIL: 接受了无效端口\n' >&2
  exit 1
fi

valid_port_range 443 || { printf 'FAIL: 单端口范围被拒绝\n' >&2; exit 1; }
valid_port_range 10000:10100 || { printf 'FAIL: 正常端口范围被拒绝\n' >&2; exit 1; }
if valid_port_range 10100:10000 || valid_port_range 1:70000 || valid_port_range '80-90'; then
  printf 'FAIL: 接受了无效端口范围\n' >&2
  exit 1
fi

valid_firewall_rule_spec 443/tcp || { printf 'FAIL: TCP 防火墙规则被拒绝\n' >&2; exit 1; }
valid_firewall_rule_spec 8443/udp || { printf 'FAIL: UDP 防火墙规则被拒绝\n' >&2; exit 1; }
valid_firewall_rule_spec 10000:10100/udp || { printf 'FAIL: UDP 端口范围被拒绝\n' >&2; exit 1; }
if valid_firewall_rule_spec 443/icmp || valid_firewall_rule_spec 70000/tcp; then
  printf 'FAIL: 接受了无效防火墙规则\n' >&2
  exit 1
fi

valid_firewall_source any || { printf 'FAIL: any 来源被拒绝\n' >&2; exit 1; }
valid_firewall_source 203.0.113.10 || { printf 'FAIL: IPv4 来源被拒绝\n' >&2; exit 1; }
valid_firewall_source 10.0.0.0/8 || { printf 'FAIL: IPv4 CIDR 被拒绝\n' >&2; exit 1; }
valid_firewall_source 2001:db8::/32 || { printf 'FAIL: IPv6 CIDR 被拒绝\n' >&2; exit 1; }
if valid_firewall_source 999.0.0.1 || valid_firewall_source 10.0.0.0/33 ||
  valid_firewall_source 'host;reboot'; then
  printf 'FAIL: 接受了无效防火墙来源\n' >&2
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

valid_username deploy || { printf 'FAIL: 正常用户名被拒绝\n' >&2; exit 1; }
if valid_username '../root' || valid_username 'Deploy User'; then
  printf 'FAIL: 接受了危险用户名\n' >&2
  exit 1
fi

valid_pid 1234 || { printf 'FAIL: 正常 PID 被拒绝\n' >&2; exit 1; }
if valid_pid 1 || valid_pid '1234;reboot'; then
  printf 'FAIL: 接受了危险 PID\n' >&2
  exit 1
fi

valid_nice_value -10 || { printf 'FAIL: 正常 nice 值被拒绝\n' >&2; exit 1; }
if valid_nice_value -21 || valid_nice_value 20; then
  printf 'FAIL: 接受了越界 nice 值\n' >&2
  exit 1
fi

valid_network_target github.com || { printf 'FAIL: 正常域名被拒绝\n' >&2; exit 1; }
valid_network_target 2001:db8::1 || { printf 'FAIL: 正常 IPv6 被拒绝\n' >&2; exit 1; }
if valid_network_target '../host' || valid_network_target 'host;reboot'; then
  printf 'FAIL: 接受了危险网络目标\n' >&2
  exit 1
fi

printf 'PASS: safety\n'
