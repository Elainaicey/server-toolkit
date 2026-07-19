#!/usr/bin/env bash
# shellcheck shell=bash
set -Eeuo pipefail
IFS=$'\n\t'

REPOSITORY="${SERVER_TOOLKIT_REPO:-Elainaicey/server-toolkit}"
REF="${SERVER_TOOLKIT_REF:-main}"
INSTALL_DIR="${SERVER_TOOLKIT_INSTALL_DIR:-/opt/server-toolkit}"
BIN_PATH="${SERVER_TOOLKIT_BIN_PATH:-/usr/local/bin/serverctl}"
DRY_RUN=0
UNINSTALL=0
TEMP_ROOT=""
STAGE_DIR=""

usage() {
  cat <<EOF
Server Toolkit 安装器

用法：
  sudo bash install.sh [选项]

选项：
  --repo OWNER/REPO     源码仓库，默认 $REPOSITORY
  --ref REF             分支或标签，默认 $REF
  --dir PATH            安装目录，默认 $INSTALL_DIR
  --bin PATH            命令入口，默认 $BIN_PATH
  --dry-run             只显示将要执行的安装或卸载
  --uninstall           卸载程序文件，保留操作日志和配置备份
  -h, --help            显示帮助
EOF
}

info() { printf '[安装器] %s\n' "$*"; }
die() { printf '[安装器][错误] %s\n' "$*" >&2; exit 1; }

read_tty() {
  local prompt="$1" answer=""
  if [[ -t 0 ]]; then
    read -r -p "$prompt" answer || true
  elif [[ -r /dev/tty ]]; then
    read -r -p "$prompt" answer </dev/tty || true
  fi
  printf '%s' "$answer"
}

confirm() {
  local answer
  answer="$(read_tty "$1 [y/N]: ")"
  [[ "$answer" =~ ^([yY]|[yY][eE][sS])$ || "$answer" == "是" || "$answer" == "确认" ]]
}

safe_install_path() {
  local path="$1"
  [[ "$path" == /* ]] || return 1
  [[ "$path" != *'/../'* && "$path" != */.. && "$path" != *'/./'* && "$path" != */. ]] || return 1
  case "$path" in
    /|/bin|/boot|/dev|/etc|/home|/lib|/lib64|/opt|/proc|/root|/run|/sbin|/srv|/sys|/tmp|/usr|/var)
      return 1
      ;;
  esac
  [[ "${path#/}" == */* ]]
}

is_toolkit_dir() {
  local path="$1"
  [[ -f "$path/bin/serverctl" && -d "$path/src/core" && -d "$path/src/features" && -f "$path/config/software.tsv" && -f "$path/VERSION" ]]
}

cleanup() {
  if [[ -n "$STAGE_DIR" && -d "$STAGE_DIR" ]]; then
    rm -rf -- "$STAGE_DIR"
  fi
  if [[ -n "$TEMP_ROOT" && -d "$TEMP_ROOT" ]]; then
    rm -rf -- "$TEMP_ROOT"
  fi
}
trap cleanup EXIT

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) [[ -n "${2:-}" ]] || die "--repo 缺少值"; REPOSITORY="$2"; shift 2 ;;
    --ref) [[ -n "${2:-}" ]] || die "--ref 缺少值"; REF="$2"; shift 2 ;;
    --dir) [[ -n "${2:-}" ]] || die "--dir 缺少值"; INSTALL_DIR="$2"; shift 2 ;;
    --bin) [[ -n "${2:-}" ]] || die "--bin 缺少值"; BIN_PATH="$2"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    --uninstall) UNINSTALL=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "未知参数：$1" ;;
  esac
done

[[ "$EUID" -eq 0 ]] || die "请使用 root 运行：sudo bash install.sh"
safe_install_path "$INSTALL_DIR" || die "不安全的安装目录：$INSTALL_DIR"
[[ "$BIN_PATH" == /* && "$BIN_PATH" != / && ! -d "$BIN_PATH" ]] || die "命令入口必须是绝对文件路径：$BIN_PATH"
[[ ! -L "$INSTALL_DIR" ]] || die "安装目录不能是符号链接：$INSTALL_DIR"

if [[ "$UNINSTALL" -eq 1 ]]; then
  if [[ ! -d "$INSTALL_DIR" ]]; then
    info "未找到安装目录。"
    exit 0
  fi
  is_toolkit_dir "$INSTALL_DIR" || die "目录不像 Server Toolkit，拒绝删除：$INSTALL_DIR"
  confirm "删除 $INSTALL_DIR 和它的命令入口？" || { info "已取消。"; exit 0; }
  if [[ "$DRY_RUN" -eq 1 ]]; then
    info "将删除 $INSTALL_DIR"
    info "若 $BIN_PATH 指向本项目，也将删除该链接"
    exit 0
  fi
  resolved_bin="$(readlink -f "$BIN_PATH" 2>/dev/null || true)"
  if [[ "$resolved_bin" == "$INSTALL_DIR/bin/serverctl" ]]; then
    rm -f -- "$BIN_PATH"
  fi
  rm -rf -- "$INSTALL_DIR"
  info "卸载完成；/var/backups/server-toolkit 与 /var/log/server-toolkit 未被删除。"
  exit 0
fi

if [[ -e "$BIN_PATH" && ! -L "$BIN_PATH" ]]; then
  die "命令入口已经存在且不是符号链接：$BIN_PATH"
fi
if [[ -L "$BIN_PATH" ]]; then
  current_target="$(readlink -f "$BIN_PATH" 2>/dev/null || true)"
  [[ "$current_target" == "$INSTALL_DIR/bin/serverctl" ]] || die "命令入口指向其他程序：$BIN_PATH"
fi
if [[ -d "$INSTALL_DIR" ]]; then
  is_toolkit_dir "$INSTALL_DIR" || die "现有目录不属于 Server Toolkit：$INSTALL_DIR"
fi

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
SOURCE_DIR=""
if is_toolkit_dir "$(dirname -- "$SCRIPT_DIR")"; then
  SOURCE_DIR="$(dirname -- "$SCRIPT_DIR")"
else
  command -v curl >/dev/null 2>&1 || die "缺少 curl"
  command -v tar >/dev/null 2>&1 || die "缺少 tar"
  TEMP_ROOT="$(mktemp -d)"
  archive="$TEMP_ROOT/source.tar.gz"
  info "下载 $REPOSITORY@$REF"
  branch_url="https://github.com/$REPOSITORY/archive/refs/heads/$REF.tar.gz"
  tag_url="https://github.com/$REPOSITORY/archive/refs/tags/$REF.tar.gz"
  if ! curl -fsSL --retry 3 --connect-timeout 10 --max-time 120 "$branch_url" -o "$archive"; then
    curl -fsSL --retry 3 --connect-timeout 10 --max-time 120 "$tag_url" -o "$archive" || die "下载源码失败"
  fi
  tar -xzf "$archive" -C "$TEMP_ROOT"
  SOURCE_DIR="$(find "$TEMP_ROOT" -mindepth 1 -maxdepth 1 -type d -print -quit)"
fi

is_toolkit_dir "$SOURCE_DIR" || die "源码结构不完整"
[[ "$SOURCE_DIR" != "$INSTALL_DIR" ]] || die "不能把项目安装到源码目录自身"

confirm "将 Server Toolkit 安装到 $INSTALL_DIR？已有安装会被完整替换。" || { info "已取消。"; exit 0; }
if [[ "$DRY_RUN" -eq 1 ]]; then
  info "将完整替换 $INSTALL_DIR"
  info "将创建命令入口 $BIN_PATH -> $INSTALL_DIR/bin/serverctl"
  exit 0
fi

parent_dir="$(dirname -- "$INSTALL_DIR")"
mkdir -p "$parent_dir" "$(dirname -- "$BIN_PATH")"
STAGE_DIR="$(mktemp -d "$parent_dir/.server-toolkit-stage.XXXXXX")"
for entry in bin src config scripts install.sh VERSION README.md CHANGELOG.md; do
  if [[ -e "$SOURCE_DIR/$entry" ]]; then
    cp -a "$SOURCE_DIR/$entry" "$STAGE_DIR/"
  fi
done
chmod 0755 "$STAGE_DIR/bin/serverctl" "$STAGE_DIR/install.sh" "$STAGE_DIR/scripts/install.sh"
find "$STAGE_DIR/src" -type f -name '*.sh' -exec chmod 0644 {} \;
is_toolkit_dir "$STAGE_DIR" || die "暂存的安装内容不完整"

old_dir=""
if [[ -d "$INSTALL_DIR" ]]; then
  old_dir="$parent_dir/.server-toolkit-old.$$"
  mv "$INSTALL_DIR" "$old_dir"
fi
if ! mv "$STAGE_DIR" "$INSTALL_DIR"; then
  if [[ -n "$old_dir" && -d "$old_dir" ]]; then
    mv "$old_dir" "$INSTALL_DIR"
  fi
  die "替换安装目录失败，旧版本已恢复"
fi
STAGE_DIR=""
if ! ln -sfn "$INSTALL_DIR/bin/serverctl" "$BIN_PATH"; then
  failed_dir="$parent_dir/.server-toolkit-failed.$$"
  mv "$INSTALL_DIR" "$failed_dir"
  if [[ -n "$old_dir" && -d "$old_dir" ]]; then
    mv "$old_dir" "$INSTALL_DIR"
  fi
  rm -rf -- "$failed_dir"
  die "创建命令入口失败，旧版本已恢复"
fi
if [[ -n "$old_dir" && -d "$old_dir" ]]; then
  rm -rf -- "$old_dir"
fi

info "安装完成：sudo serverctl"
