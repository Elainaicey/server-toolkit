#!/usr/bin/env bash

OH_MY_ZSH_REPOSITORY="https://github.com/ohmyzsh/ohmyzsh.git"
OH_MY_ZSH_BLOCK_BEGIN="# BEGIN Server Toolkit: Oh My Zsh"
OH_MY_ZSH_BLOCK_END="# END Server Toolkit: Oh My Zsh"

software_target_user() {
  local user="${SUDO_USER:-}"
  [[ -n "$user" && "$user" != "root" ]] || user="$(id -un)"
  [[ "$user" =~ ^[a-zA-Z0-9_.-]+$ ]] || die "目标用户名格式无效：$user"
  getent passwd "$user" >/dev/null 2>&1 || die "无法读取目标用户信息：$user"
  printf '%s' "$user"
}

software_target_home() {
  local user="${1:-$(software_target_user)}" home
  home="$(getent passwd "$user" | awk -F: 'NR == 1 {print $6}')"
  [[ "$home" == /* && "$home" != "/" ]] || die "目标用户主目录不安全：${home:-未知}"
  printf '%s' "$home"
}

software_run_as_target() {
  local user="$1" home="$2"
  shift 2
  if [[ "$EUID" -eq 0 && "$user" != "root" ]]; then
    command_exists runuser || die "系统缺少 runuser，无法以 $user 身份执行命令。"
    run runuser -u "$user" -- env HOME="$home" "$@"
  else
    run env HOME="$home" "$@"
  fi
}

software_oh_my_zsh_path() {
  local user home
  user="$(software_target_user)"
  home="$(software_target_home "$user")"
  printf '%s/.oh-my-zsh' "$home"
}

software_oh_my_zsh_official_remote() {
  case "${1:-}" in
    https://github.com/ohmyzsh/ohmyzsh|https://github.com/ohmyzsh/ohmyzsh.git|git@github.com:ohmyzsh/ohmyzsh.git) return 0 ;;
    *) return 1 ;;
  esac
}

software_oh_my_zsh_installed() {
  local directory remote
  directory="$(software_oh_my_zsh_path)"
  [[ -f "$directory/oh-my-zsh.sh" && -d "$directory/.git" ]] || return 1
  remote="$(git -C "$directory" remote get-url origin 2>/dev/null || true)"
  software_oh_my_zsh_official_remote "$remote"
}

software_oh_my_zsh_version() {
  local directory
  directory="$(software_oh_my_zsh_path)"
  software_oh_my_zsh_installed || return 0
  git -C "$directory" rev-parse --short=12 HEAD 2>/dev/null || true
}

software_oh_my_zsh_configure() {
  local user="$1" home="$2" zshrc="$2/.zshrc" separator=""
  if [[ -f "$zshrc" ]] && grep -Fq 'oh-my-zsh.sh' "$zshrc"; then
    info "$zshrc 已包含 Oh My Zsh 配置，不重复写入。"
    return 0
  fi
  backup_file "$zshrc"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    info "将向 $zshrc 添加 Server Toolkit 托管的 Oh My Zsh 配置块。"
    return 0
  fi
  [[ ! -s "$zshrc" ]] || separator=$'\n'
  printf '%s%s\n%s\n%s\n%s\n%s\n%s\n' \
    "$separator" \
    "$OH_MY_ZSH_BLOCK_BEGIN" \
    "export ZSH=\"\$HOME/.oh-my-zsh\"" \
    'ZSH_THEME="robbyrussell"' \
    'plugins=(git)' \
    "source \"\$ZSH/oh-my-zsh.sh\"" \
    "$OH_MY_ZSH_BLOCK_END" >>"$zshrc"
  if [[ "$EUID" -eq 0 ]]; then chown "$user":"$(id -gn "$user")" "$zshrc"; fi
}

software_oh_my_zsh_remove_config() {
  local user="$1" home="$2" zshrc="$2/.zshrc" temporary
  [[ -f "$zshrc" ]] || return 0
  grep -Fq "$OH_MY_ZSH_BLOCK_BEGIN" "$zshrc" || return 0
  if ! grep -Fq "$OH_MY_ZSH_BLOCK_END" "$zshrc"; then
    warn "$zshrc 中的托管配置块不完整，为避免误删已保留原文件。"
    return 1
  fi
  backup_file "$zshrc"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    info "将从 $zshrc 移除 Server Toolkit 托管的配置块。"
    return 0
  fi
  temporary="$(mktemp)"
  awk -v begin="$OH_MY_ZSH_BLOCK_BEGIN" -v end="$OH_MY_ZSH_BLOCK_END" '
    $0 == begin {managed=1; next}
    $0 == end && managed {managed=0; next}
    !managed {print}
  ' "$zshrc" >"$temporary"
  install -m 0644 "$temporary" "$zshrc"
  rm -f "$temporary"
  if [[ "$EUID" -eq 0 ]]; then chown "$user":"$(id -gn "$user")" "$zshrc"; fi
}

software_install_oh_my_zsh() {
  local user home directory zsh_path
  user="$(software_target_user)"
  home="$(software_target_home "$user")"
  directory="$home/.oh-my-zsh"
  safe_managed_path "$directory" || die "Oh My Zsh 目标路径不安全：$directory"
  if [[ -e "$directory" || -L "$directory" ]]; then
    software_oh_my_zsh_installed && { info "Oh My Zsh 已经安装。"; return 0; }
    die "目标目录已存在且不是受支持的官方 Oh My Zsh 仓库：$directory"
  fi
  package_install zsh git
  info "将为用户 $user 安装 Oh My Zsh 到 $directory。"
  software_run_as_target "$user" "$home" git clone --depth=1 "$OH_MY_ZSH_REPOSITORY" "$directory"
  software_oh_my_zsh_configure "$user" "$home"
  zsh_path="$(command -v zsh 2>/dev/null || printf '/usr/bin/zsh')"
  if confirm "是否将 $user 的默认 Shell 切换为 $zsh_path？"; then
    run chsh -s "$zsh_path" "$user"
  else
    info "已保留 $user 当前的默认 Shell；可稍后执行 chsh -s $zsh_path $user。"
  fi
}

software_update_oh_my_zsh() {
  local user home directory remote
  user="$(software_target_user)"
  home="$(software_target_home "$user")"
  directory="$home/.oh-my-zsh"
  software_oh_my_zsh_installed || die "没有检测到受支持的官方 Oh My Zsh 安装。"
  remote="$(git -C "$directory" remote get-url origin 2>/dev/null || true)"
  software_oh_my_zsh_official_remote "$remote" || die "拒绝更新来源不明的 Oh My Zsh 仓库。"
  software_run_as_target "$user" "$home" zsh "$directory/tools/upgrade.sh"
}

software_remove_oh_my_zsh() {
  local user home directory remote
  user="$(software_target_user)"
  home="$(software_target_home "$user")"
  directory="$home/.oh-my-zsh"
  safe_managed_path "$directory" || die "Oh My Zsh 目标路径不安全：$directory"
  software_oh_my_zsh_installed || die "没有检测到受支持的官方 Oh My Zsh 安装。"
  remote="$(git -C "$directory" remote get-url origin 2>/dev/null || true)"
  software_oh_my_zsh_official_remote "$remote" || die "拒绝删除来源不明的目录：$directory"
  software_oh_my_zsh_remove_config "$user" "$home"
  software_run_as_target "$user" "$home" rm -rf -- "$directory"
  info "已保留 Zsh、Git、用户的其他配置和默认 Shell 设置。"
}
