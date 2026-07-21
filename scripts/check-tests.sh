#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd)"
cd "$ROOT_DIR"

printf '[tests] 离线单元测试\n'
for test_file in tests/test_*.sh; do
  bash "$test_file"
done

printf '[tests] 软件目录格式\n'
awk -F '|' '
  !/^#/ && NF != 6 { print "invalid catalog line " NR; failed=1 }
  END { exit failed }
' config/software.tsv

printf '[tests] CLI 冒烟测试\n'
[[ "$(bash bin/serverctl version)" == "Server Toolkit 0.1.0" ]]
bash bin/serverctl --help | grep -q '一次只接受一个软件 ID'
bash bin/serverctl --help | grep -q 'update ID'
bash bin/serverctl --help | grep -q 'health'
bash bin/serverctl --help | grep -q 'dns \[域名\]'
bash bin/serverctl --help | grep -q 'logs SERVICE'
bash install.sh --help | grep -q 'Server Toolkit 安装器'
bash scripts/install.sh --help | grep -q -- '--purge-data'

printf 'PASS: tests\n'
