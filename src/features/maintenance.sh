#!/usr/bin/env bash

toolkit_about() {
  ui_page "关于 Server Toolkit" "版本、路径与项目资源"
  ui_kv "版本" "$SERVERCTL_VERSION"
  ui_kv "安装目录" "$ROOT_DIR"
  ui_kv "软件目录" "$SOFTWARE_CATALOG"
  ui_kv "配置备份" "$BACKUP_ROOT"
  ui_kv "操作记录" "$AUDIT_LOG"
  ui_kv "项目主页" "https://github.com/Elainaicey/server-toolkit"
}

toolkit_uninstall() {
  local choice installer install_metadata bin_path
  installer="$ROOT_DIR/scripts/install.sh"
  install_metadata="$ROOT_DIR/config/installation.conf"
  bin_path="/usr/local/bin/serverctl"
  [[ -f "$installer" ]] || die "没有找到卸载器：$installer"
  if [[ -r "$install_metadata" ]]; then
    # 该文件由安装器生成，只包含经过 shell 转义的安装路径。
    # shellcheck source=/dev/null
    . "$install_metadata"
    bin_path="${SERVER_TOOLKIT_BIN_PATH:-$bin_path}"
    export SERVER_TOOLKIT_BACKUP_ROOT SERVER_TOOLKIT_LOG_ROOT SERVER_TOOLKIT_STATE_ROOT
  fi

  ui_page "卸载 Server Toolkit" "安全删除程序文件与可选的项目数据"
  ui_danger "卸载会立即结束当前控制台。"
  ui_item 1 "仅卸载程序" "删除安装目录和 serverctl 命令，保留日志与备份"
  ui_item 2 "彻底清除项目数据" "同时删除项目日志、备份和状态数据"
  ui_item 0 "取消"
  ui_note "已安装的软件和系统配置不会被擅自删除；需要回滚时请先使用备份中心。"
  choice="$(read_input "请选择" "0")"
  case "$choice" in
    1) exec bash "$installer" --uninstall --dir "$ROOT_DIR" --bin "$bin_path" ;;
    2) exec bash "$installer" --uninstall --purge-data --dir "$ROOT_DIR" --bin "$bin_path" ;;
    0) return 0 ;;
    *) warn "未知选项"; return 1 ;;
  esac
}
