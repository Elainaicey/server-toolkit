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
  # SC1090/SC1091: 项目采用运行时模块加载，静态分析无法解析动态 ROOT_DIR。
  shellcheck -e SC1090,SC1091 serverctl.sh install.sh lib/*.sh modules/*.sh scripts/*.sh tests/*.sh
else
  printf '[check] 未安装 shellcheck，跳过静态检查\n'
fi

printf '[check] 单元测试\n'
for test_file in tests/test_*.sh; do
  bash "$test_file"
done

printf '[check] 全部通过\n'
