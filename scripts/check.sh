#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd)"
cd "$ROOT_DIR"

printf '[check] Bash 语法\n'
while IFS= read -r file; do
  bash -n "$file"
done < <(find bin src scripts tests -type f \( -name '*.sh' -o -path 'bin/serverctl' \) -print | sort)
bash -n install.sh

if command -v shellcheck >/dev/null 2>&1; then
  printf '[check] ShellCheck（逐文件）\n'
  # SC1090/SC1091: 入口根据运行时 ROOT_DIR 加载项目文件。
  shellcheck_status=0
  while IFS= read -r file; do
    shellcheck -e SC1090,SC1091 "$file" || shellcheck_status=1
  done < <(
    printf '%s\n' install.sh
    find bin src scripts tests -type f \( -name '*.sh' -o -path 'bin/serverctl' \) -print | sort
  )
  (( shellcheck_status == 0 )) || exit 1
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
' config/software.tsv

printf '[check] CLI 冒烟测试\n'
[[ "$(bash bin/serverctl version)" == "Server Toolkit 0.1.0" ]]
bash bin/serverctl --help | grep -q '一次只接受一个软件 ID'
bash bin/serverctl --help | grep -q 'update ID'
bash bin/serverctl --help | grep -q 'health'
bash bin/serverctl --help | grep -q 'dns \[域名\]'
bash bin/serverctl --help | grep -q 'logs SERVICE'
bash install.sh --help | grep -q 'Server Toolkit 安装器'
bash scripts/install.sh --help | grep -q -- '--purge-data'

printf '[check] 发布元数据\n'
version="$(tr -d '[:space:]' < VERSION)"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
grep -Fqx "## $version" docs/CHANGELOG.md
grep -Fq 'MIT License' LICENSE
grep -Fq 'Copyright (c) 2026 Elainaicey' LICENSE
if grep -Fq 'img.shields.io' README.md; then
  printf 'README 不应依赖第三方 Shields.io 徽章\n' >&2
  exit 1
fi

printf '[check] 全部通过\n'
