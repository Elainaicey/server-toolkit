#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd)"
cd "$ROOT_DIR"

mapfile -t repository_files < <(
  while IFS= read -r file; do
    [[ -e "$file" || -L "$file" ]] && printf '%s\n' "$file"
  done < <(git ls-files --cached --others --exclude-standard | LC_ALL=C sort -u)
)
(( ${#repository_files[@]} > 0 )) || {
  printf 'FAIL: 仓库中没有可检查文件\n' >&2
  exit 1
}

declare -A category_counts=()
classification_failed=0

printf '[repository] 文件分类与 Git 属性\n'
for file in "${repository_files[@]}"; do
  category=""
  case "$file" in
    install.sh|*.sh|bin/serverctl) category="shell" ;;
    *.md) category="markdown" ;;
    .github/workflows/*.yml) category="workflow" ;;
    .github/assets/badges/*.svg) category="svg" ;;
    *.tsv) category="catalog" ;;
    .gitattributes|.gitignore|LICENSE|VERSION) category="metadata" ;;
    *)
      printf 'FAIL: 未归类文件：%s\n' "$file" >&2
      classification_failed=1
      continue
      ;;
  esac

  if [[ ! -f "$file" || -L "$file" ]]; then
    printf 'FAIL: 文件必须是普通文件且不能是符号链接：%s\n' "$file" >&2
    classification_failed=1
    continue
  fi

  mode="$(git ls-files -s -- "$file" | awk 'NR==1 {print $1}')"
  if [[ -n "$mode" && "$mode" != "100644" ]]; then
    printf 'FAIL: 文件模式必须为 100644：%s (%s)\n' "$file" "$mode" >&2
    classification_failed=1
  fi

  eol="$(git check-attr eol -- "$file" | sed 's/^.*: //')"
  if [[ "$eol" != "lf" ]]; then
    printf 'FAIL: 文件没有声明 LF 换行：%s (%s)\n' "$file" "${eol:-unspecified}" >&2
    classification_failed=1
  fi

  category_counts["$category"]=$(( ${category_counts[$category]:-0} + 1 ))
done

(( classification_failed == 0 )) || exit 1

python_bin="$(command -v python3 || command -v python || true)"
[[ -n "$python_bin" ]] || {
  printf 'FAIL: 全文件验证需要 Python 3\n' >&2
  exit 1
}
"$python_bin" -c 'import sys; raise SystemExit(sys.version_info < (3, 8))' || {
  printf 'FAIL: 全文件验证需要 Python 3.8 或更高版本\n' >&2
  exit 1
}

printf '[repository] UTF-8、LF、尾随空白与内部链接\n'
"$python_bin" - "${repository_files[@]}" <<'PY'
from __future__ import annotations

import re
import sys
import urllib.parse
import xml.etree.ElementTree as ET
from pathlib import Path

root = Path.cwd().resolve()
paths = [Path(value) for value in sys.argv[1:]]
failures: list[str] = []
seen_casefold: dict[str, str] = {}
link_pattern = re.compile(r"]\(([^)]+)\)")

for path in paths:
    folded = path.as_posix().casefold()
    if folded in seen_casefold:
        failures.append(
            f"大小写不敏感文件名冲突：{seen_casefold[folded]} / {path.as_posix()}"
        )
    else:
        seen_casefold[folded] = path.as_posix()

    data = path.read_bytes()
    if not data:
        failures.append(f"空文件：{path.as_posix()}")
        continue
    if data.startswith(b"\xef\xbb\xbf"):
        failures.append(f"不允许 UTF-8 BOM：{path.as_posix()}")
    if b"\x00" in data:
        failures.append(f"文本仓库中出现 NUL 字节：{path.as_posix()}")
    if b"\r" in data:
        failures.append(f"检测到 CR/CRLF 换行：{path.as_posix()}")
    if not data.endswith(b"\n"):
        failures.append(f"文件末尾缺少换行：{path.as_posix()}")
    try:
        text = data.decode("utf-8")
    except UnicodeDecodeError as error:
        failures.append(f"不是有效 UTF-8：{path.as_posix()} ({error})")
        continue

    for number, line in enumerate(text.splitlines(), 1):
        if line.endswith((" ", "\t")):
            failures.append(f"尾随空白：{path.as_posix()}:{number}")

    suffix = path.suffix.lower()
    if suffix == ".md":
        if not any(line.startswith("# ") for line in text.splitlines()):
            failures.append(f"Markdown 缺少一级标题：{path.as_posix()}")
        for raw_target in link_pattern.findall(text):
            target = raw_target.strip().strip("<>")
            if not target or target.startswith(("#", "http://", "https://", "mailto:")):
                continue
            target = target.split(maxsplit=1)[0].split("#", 1)[0]
            target = urllib.parse.unquote(target)
            resolved = (path.parent / target).resolve()
            try:
                resolved.relative_to(root)
            except ValueError:
                failures.append(f"Markdown 链接越出仓库：{path.as_posix()} -> {target}")
                continue
            if not resolved.exists():
                failures.append(f"Markdown 内部链接不存在：{path.as_posix()} -> {target}")

    elif suffix == ".svg":
        try:
            svg_root = ET.fromstring(text)
            if not svg_root.tag.endswith("svg"):
                failures.append(f"SVG 根元素无效：{path.as_posix()}")
        except ET.ParseError as error:
            failures.append(f"SVG XML 无效：{path.as_posix()} ({error})")

    elif path.as_posix().startswith(".github/workflows/"):
        required = ("name:", "on:", "jobs:")
        for key in required:
            if not any(line.startswith(key) for line in text.splitlines()):
                failures.append(f"工作流缺少顶层 {key}：{path.as_posix()}")

    elif suffix == ".tsv":
        for number, line in enumerate(text.splitlines(), 1):
            if line.startswith("#") or not line:
                continue
            if len(line.split("|")) != 6:
                failures.append(f"软件目录字段数不是 6：{path.as_posix()}:{number}")

if failures:
    for failure in failures:
        print(f"FAIL: {failure}", file=sys.stderr)
    raise SystemExit(1)
PY

if command -v yamllint >/dev/null 2>&1; then
  printf '[repository] YAML 语法与格式\n'
  yamllint -d '{extends: default, rules: {document-start: disable, line-length: disable, truthy: disable}}' .github/workflows
elif [[ "${REQUIRE_YAMLLINT:-0}" == "1" ]]; then
  printf 'FAIL: 当前检查要求 yamllint，但系统中没有该命令\n' >&2
  exit 1
else
  printf '[repository] 未安装 yamllint，仅执行内置工作流结构检查\n'
fi

printf '[repository] 项目元数据\n'
version="$(tr -d '[:space:]' < VERSION)"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
  printf 'FAIL: VERSION 不是语义版本：%s\n' "$version" >&2
  exit 1
}
grep -Fqx "## $version" docs/CHANGELOG.md || {
  printf 'FAIL: docs/CHANGELOG.md 缺少 %s 发布章节\n' "$version" >&2
  exit 1
}
grep -Fq 'MIT License' LICENSE || {
  printf 'FAIL: LICENSE 不是 MIT License\n' >&2
  exit 1
}
grep -Fq 'Copyright (c) 2026 Elainaicey' LICENSE || {
  printf 'FAIL: LICENSE 缺少项目版权声明\n' >&2
  exit 1
}
grep -Fq "$version" .github/assets/badges/version.svg || {
  printf 'FAIL: 版本徽章与 VERSION 不一致\n' >&2
  exit 1
}
if grep -Fq 'img.shields.io' README.md; then
  printf 'FAIL: README 不应依赖第三方 Shields.io 徽章\n' >&2
  exit 1
fi

for category in shell markdown workflow svg catalog metadata; do
  printf '  %-10s %s\n' "$category" "${category_counts[$category]:-0}"
done
printf 'PASS: repository files (%s)\n' "${#repository_files[@]}"
