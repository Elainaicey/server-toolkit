#!/usr/bin/env bash
# shellcheck shell=bash
set -Eeuo pipefail
IFS=$'\n\t'

REPO="${SERVER_TOOLKIT_REPO:-Elainaicey/server-toolkit}"
REF="${SERVER_TOOLKIT_REF:-main}"
INSTALL_DIR="${SERVER_TOOLKIT_INSTALL_DIR:-/opt/server-toolkit}"
BIN_PATH="${SERVER_TOOLKIT_BIN_PATH:-/usr/local/bin/serverctl}"
RUN_PROFILE=""
RUN_MENU=1
ASSUME_YES=0
DRY_RUN=0

usage() {
  cat <<USAGE
Server Toolkit 安装器

用法：
  sudo bash install.sh [选项]

选项：
  --repo OWNER/REPO     GitHub 仓库，默认：${REPO}
  --ref REF             分支或版本标签，默认：${REF}
  --dir PATH            安装目录，默认：${INSTALL_DIR}
  --bin PATH            命令入口，默认：${BIN_PATH}
  --profile NAME        安装后直接执行 profile，例如 proxy/docker/web/dev/full
  --menu                安装后打开中文交互菜单，默认开启
  --no-menu             安装后不打开菜单
  --yes, -y             profile 执行时自动确认
  --dry-run             只打印动作，不真正修改
  -h, --help            查看帮助

推荐一行交互安装：
  bash <(curl -fsSL https://raw.githubusercontent.com/${REPO}/${REF}/install.sh)

推荐稳妥安装：
  curl -fsSL https://raw.githubusercontent.com/${REPO}/${REF}/install.sh -o /tmp/server-toolkit-install.sh
  bash -n /tmp/server-toolkit-install.sh
  sudo bash /tmp/server-toolkit-install.sh

无人值守示例：
  sudo bash /tmp/server-toolkit-install.sh --profile proxy --yes --no-menu
USAGE
}

log() { printf '[安装器] %s\n' "$*"; }
die() { printf '[安装器][错误] %s\n' "$*" >&2; exit 1; }
run() {
  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf '[DRY-RUN]'
    printf ' %q' "$@"
    printf '\n'
  else
    "$@"
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO="${2:-}"; shift 2 ;;
    --ref) REF="${2:-}"; shift 2 ;;
    --dir) INSTALL_DIR="${2:-}"; shift 2 ;;
    --bin) BIN_PATH="${2:-}"; shift 2 ;;
    --profile) RUN_PROFILE="${2:-}"; RUN_MENU=0; shift 2 ;;
    --menu) RUN_MENU=1; shift ;;
    --no-menu) RUN_MENU=0; shift ;;
    --yes|-y) ASSUME_YES=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "未知参数：$1" ;;
  esac
done

[[ "${EUID}" -eq 0 ]] || die "请使用 root 运行：sudo bash install.sh"
command -v curl >/dev/null 2>&1 || die "缺少 curl"
command -v tar >/dev/null 2>&1 || die "缺少 tar"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
SRC_DIR=""
TMP_DIR=""

if [[ -f "$SCRIPT_DIR/serverctl.sh" && -d "$SCRIPT_DIR/lib" && -d "$SCRIPT_DIR/modules" ]]; then
  SRC_DIR="$SCRIPT_DIR"
  log "使用本地源码：$SRC_DIR"
else
  TMP_DIR="$(mktemp -d)"
  archive="$TMP_DIR/source.tar.gz"
  head_url="https://github.com/${REPO}/archive/refs/heads/${REF}.tar.gz"
  tag_url="https://github.com/${REPO}/archive/refs/tags/${REF}.tar.gz"
  log "正在下载 ${REPO}@${REF}"
  if ! curl -fL --connect-timeout 10 --max-time 120 "$head_url" -o "$archive"; then
    curl -fL --connect-timeout 10 --max-time 120 "$tag_url" -o "$archive" || die "下载失败"
  fi
  tar -xzf "$archive" -C "$TMP_DIR"
  SRC_DIR="$(find "$TMP_DIR" -mindepth 1 -maxdepth 1 -type d | head -n1)"
fi

[[ -f "$SRC_DIR/serverctl.sh" ]] || die "源码中缺少 serverctl.sh"
[[ -d "$SRC_DIR/lib" && -d "$SRC_DIR/modules" && -d "$SRC_DIR/profiles" ]] || die "源码目录不完整"

log "正在安装到 $INSTALL_DIR"
run mkdir -p "$INSTALL_DIR"
run cp -a "$SRC_DIR"/. "$INSTALL_DIR"/
run chmod +x "$INSTALL_DIR/serverctl.sh" "$INSTALL_DIR/install.sh"
run find "$INSTALL_DIR" -type f -name '*.sh' -exec chmod 0644 {} \;
run chmod +x "$INSTALL_DIR/serverctl.sh" "$INSTALL_DIR/install.sh"

log "正在创建命令入口：$BIN_PATH"
run ln -sf "$INSTALL_DIR/serverctl.sh" "$BIN_PATH"

if [[ -n "$RUN_PROFILE" ]]; then
  log "正在执行 profile：$RUN_PROFILE"
  args=(install --profile "$RUN_PROFILE")
  [[ "$ASSUME_YES" -eq 1 ]] && args+=(--yes)
  [[ "$DRY_RUN" -eq 1 ]] && args+=(--dry-run)
  run "$BIN_PATH" "${args[@]}"
elif [[ "$RUN_MENU" -eq 1 ]]; then
  log "安装完成，正在打开中文交互菜单。"
  run "$BIN_PATH" menu
fi

[[ -n "$TMP_DIR" && -d "$TMP_DIR" ]] && rm -rf "$TMP_DIR"
log "完成。以后可直接运行：sudo serverctl"
