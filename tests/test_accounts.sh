#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd)"
# shellcheck source=../src/core/runtime.sh
. "$ROOT_DIR/src/core/runtime.sh"
# shellcheck source=../src/features/system/accounts.sh
. "$ROOT_DIR/src/features/system/accounts.sh"

getent() {
  if [[ "${1:-}" == "passwd" && "${2:-}" == "root" ]]; then
    printf 'root:x:0:0:root:/root:/bin/bash\n'
    return 0
  fi
  return 2
}

valid_username alice || { printf 'FAIL: 正常用户名被拒绝\n' >&2; exit 1; }
valid_username deploy-user || { printf 'FAIL: 带短横线的用户名被拒绝\n' >&2; exit 1; }
if valid_username 'Alice' || valid_username '../root' || valid_username 'user name'; then
  printf 'FAIL: 接受了危险用户名\n' >&2
  exit 1
fi

valid_ssh_public_key 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIElaWnaiceyServerToolkitExampleKey00001 alice@example' || {
  printf 'FAIL: 正常 SSH 公钥被拒绝\n' >&2
  exit 1
}
if valid_ssh_public_key 'command="reboot" ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIElaWnaiceyServerToolkitExampleKey00001' ||
  valid_ssh_public_key 'ssh-ed25519 short' ||
  valid_ssh_public_key 'not-a-key AAAAC3NzaC1lZDI1NTE5AAAAIElaWnaiceyServerToolkitExampleKey00001' ||
  valid_ssh_public_key $'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIElaWnaiceyServerToolkitExampleKey00001\e[31m'; then
  printf 'FAIL: 接受了无效 SSH 公钥\n' >&2
  exit 1
fi

account_home_is_safe /home/alice || { printf 'FAIL: 正常用户主目录被拒绝\n' >&2; exit 1; }
account_home_is_safe /root || { printf 'FAIL: root 主目录被拒绝\n' >&2; exit 1; }
if account_home_is_safe / || account_home_is_safe home/alice || account_home_is_safe /home/../root; then
  printf 'FAIL: 接受了危险用户主目录\n' >&2
  exit 1
fi
if account_home_is_safe $'/home/alice\e[31m' || account_home_is_safe '/home/alice user'; then
  printf 'FAIL: 接受了包含控制字符或空格的用户主目录\n' >&2
  exit 1
fi

account_exists root || { printf 'FAIL: 无法识别 root 账户\n' >&2; exit 1; }
[[ "$(account_field root 3)" == "0" ]] || { printf 'FAIL: root UID 解析错误\n' >&2; exit 1; }
account_is_protected root || { printf 'FAIL: root 未被列为受保护账户\n' >&2; exit 1; }

printf 'PASS: accounts\n'
