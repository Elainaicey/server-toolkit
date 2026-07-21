#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd)"
cd "$ROOT_DIR"

bash scripts/check-repository.sh
bash scripts/check-shell.sh
bash scripts/check-tests.sh

printf '[check] 全部通过\n'
