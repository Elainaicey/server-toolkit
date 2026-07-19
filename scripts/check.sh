#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd)"
cd "$ROOT_DIR"

printf '[check] Bash 语法\n'
while IFS= read -r file; do
  bash -n "$file"
done < <(find . -type f -name '*.sh' -not -path './.git/*' | sort)

if command -v shellcheck >/dev/null 2>&1; then
  printf '[check] ShellCheck\n'
  # SC1090/SC1091: 入口根据运行时 ROOT_DIR 加载项目文件。
  shellcheck -e SC1090,SC1091 serverctl.sh install.sh lib/*.sh features/*.sh scripts/*.sh tests/*.sh
else
  printf '[check] 未安装 shellcheck，跳过静态检查\n'
fi

printf '[check] 单元测试\n'
for test_file in tests/test_*.sh; do
  bash "$test_file"
done

printf '[check] 软件目录格式\n'
awk -F '|' '
  !/^#/ && NF != 6 { print "invalid catalog line " NR; failed=1 }
  END { exit failed }
' catalog/software.tsv

printf '[check] CLI 冒烟测试\n'
[[ "$(bash serverctl.sh version)" == "Server Toolkit 0.1.0" ]]
bash serverctl.sh --help | grep -q '每次 install 只接受一个软件 ID'
bash install.sh --help | grep -q 'Server Toolkit 安装器'

printf '[check] 全部通过\n'
