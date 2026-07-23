#!/usr/bin/env bash

account_exists() {
  valid_username "${1:-}" && getent passwd "$1" >/dev/null 2>&1
}

account_record() {
  account_exists "$1" || return 1
  getent passwd "$1" | head -n 1
}

account_field() {
  local user="$1" field="$2" record
  record="$(account_record "$user")" || return 1
  awk -F: -v field="$field" '{print $field}' <<<"$record"
}

account_password_state() {
  local user="$1" state
  state="$(passwd -S "$user" 2>/dev/null | awk '{print $2}' || true)"
  case "$state" in
    L|LK) printf 'locked' ;;
    P|PS) printf 'password' ;;
    NP) printf 'no-password' ;;
    *) printf 'unknown' ;;
  esac
}

account_password_label() {
  case "$(account_password_state "$1")" in
    locked) printf '已锁定' ;;
    password) printf '已设置密码' ;;
    no-password) printf '未设置密码' ;;
    *) printf '未知' ;;
  esac
}

account_in_sudo() {
  account_exists "$1" || return 1
  id -nG "$1" 2>/dev/null | tr ' ' '\n' | grep -Fxq sudo
}

account_is_protected() {
  local user="$1" uid operator
  uid="$(account_field "$user" 3)" || return 0
  operator="${SUDO_USER:-$(id -un 2>/dev/null || printf 'root')}"
  [[ "$uid" == "0" || "$user" == "$operator" ]]
}

account_home_is_safe() {
  local home="${1:-}"
  [[ "$home" == /* && "$home" != "/" ]] || return 1
  [[ "$home" =~ ^/[a-zA-Z0-9._/-]+$ ]] || return 1
  [[ "$home" != *'/../'* && "$home" != */.. && "$home" != *'/./'* && "$home" != */. ]]
}

account_authorized_keys_path() {
  local user="$1" home
  home="$(account_field "$user" 6)" || return 1
  account_home_is_safe "$home" || return 1
  printf '%s/.ssh/authorized_keys' "${home%/}"
}

account_key_count() {
  local path
  path="$(account_authorized_keys_path "$1")" || { printf '0'; return 0; }
  if [[ -r "$path" ]]; then
    awk 'NF && $1 !~ /^#/ {count++} END{print count+0}' "$path"
  elif [[ -e "$path" ]]; then
    printf '不可读'
  else
    printf '0'
  fi
}

account_online_count() {
  who 2>/dev/null | awk -v user="$1" '$1==user{count++} END{print count+0}'
}

account_list() {
  local uid_min user _password uid gid comment home shell state sudo online state_color
  uid_min="$(awk '$1=="UID_MIN"{print $2; exit}' /etc/login.defs 2>/dev/null || true)"
  [[ "$uid_min" =~ ^[0-9]+$ ]] || uid_min=1000
  printf '  %b' "$MUTED"
  ui_pad "USER" 18
  ui_pad "UID" 7
  ui_pad "STATE" 12
  ui_pad "SUDO" 8
  ui_pad "ONLINE" 8
  printf 'SHELL%b\n' "$NC"
  while IFS=: read -r user _password uid gid comment home shell; do
    valid_username "$user" || continue
    if (( uid != 0 && (uid < uid_min || uid >= 65534) )); then continue; fi
    state="$(account_password_label "$user")"
    if account_in_sudo "$user"; then sudo="yes"; else sudo="no"; fi
    online="$(account_online_count "$user")"
    if [[ "$state" == "已锁定" ]]; then state_color="$YELLOW"; else state_color="$GREEN"; fi
    printf '  '
    ui_pad "$user" 18
    ui_pad "$uid" 7
    printf '%b' "$state_color"
    ui_pad "$state" 12
    printf '%b' "$NC"
    ui_pad "$sudo" 8
    ui_pad "$online" 8
    printf '%s\n' "$(terminal_safe_text "${shell:-—}")"
  done < <(getent passwd)
}

account_sessions() {
  local user="${1:-}"
  ui_page "登录会话" "当前连接与最近登录记录"
  ui_section "当前会话" "primary"
  if [[ -n "$user" ]]; then
    who 2>/dev/null | awk -v user="$user" '$1==user' || true
  else
    who 2>/dev/null || true
  fi
  ui_section "最近登录" "accent"
  if [[ -n "$user" ]]; then
    last -n 30 "$user" 2>/dev/null || ui_empty "没有可显示的登录记录"
  else
    last -n 30 2>/dev/null || ui_empty "没有可显示的登录记录"
  fi
}

account_keys_show() {
  local user="$1" path line fingerprint found=0
  path="$(account_authorized_keys_path "$user")" || { warn "账户主目录不安全或不可用。"; return 1; }
  ui_page "SSH 公钥 / $user" "只显示指纹，不输出完整公钥内容"
  ui_kv "配置文件" "$path"
  if [[ -e "$path" && ! -r "$path" ]]; then ui_empty "当前权限无法读取 authorized_keys"; return 0; fi
  if [[ ! -e "$path" ]]; then ui_empty "尚未配置 authorized_keys"; return 0; fi
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -n "$line" && "$line" != \#* ]] || continue
    found=1
    if command_exists ssh-keygen; then
      fingerprint="$(printf '%s\n' "$line" | ssh-keygen -lf - 2>/dev/null || true)"
      if [[ -n "$fingerprint" ]]; then
        printf '  %s\n' "$(terminal_safe_text "$fingerprint")"
      else
        printf '  无法解析的公钥条目\n'
      fi
    else
      printf '  已配置公钥（安装 openssh-client 后可显示指纹）\n'
    fi
  done <"$path"
  (( found == 1 )) || ui_empty "文件中没有有效公钥条目"
}

account_key_add() {
  local user="$1" key path home uid gid ssh_dir
  account_exists "$user" || { warn "账户不存在：$user"; return 1; }
  path="$(account_authorized_keys_path "$user")" || { warn "账户主目录不安全或不可用。"; return 1; }
  home="$(account_field "$user" 6)"
  uid="$(account_field "$user" 3)"
  gid="$(account_field "$user" 4)"
  ssh_dir="${path%/*}"
  if [[ -L "$home" || -L "$ssh_dir" || -L "$path" ]]; then
    warn "拒绝写入符号链接形式的主目录、.ssh 或 authorized_keys。"
    return 1
  fi
  if [[ -e "$path" && ! -f "$path" ]]; then
    warn "authorized_keys 已存在但不是普通文件。"
    return 1
  fi
  if [[ -f "$path" && "$(stat -c '%h' "$path" 2>/dev/null || printf '2')" != "1" ]]; then
    warn "authorized_keys 存在多个硬链接，拒绝修改。"
    return 1
  fi
  key="$(read_input "粘贴一行 SSH 公钥" "")"
  [[ -n "$key" ]] || return 0
  valid_ssh_public_key "$key" || { warn "SSH 公钥格式无效，仅接受受支持的 OpenSSH 公钥行。"; return 1; }
  if [[ -r "$path" ]] && grep -Fxq "$key" "$path"; then
    warn "该公钥已经存在。"
    return 1
  fi
  ui_panel_begin "写入计划"
  ui_panel_kv "账户" "$user"
  ui_panel_kv "主目录" "$home"
  ui_panel_kv "目标" "$path"
  ui_panel_kv "权限" ".ssh 0700 / authorized_keys 0600"
  ui_panel_end
  confirm "为 $user 添加这把 SSH 公钥？" || return 0
  require_root
  backup_file "$path" || { warn "无法备份现有 authorized_keys。"; return 1; }
  if [[ "$DRY_RUN" -eq 1 ]]; then
    info "将创建 $ssh_dir 并向 $path 追加已校验的 SSH 公钥"
  else
    install -d -m 0700 -o "$uid" -g "$gid" "$ssh_dir" || { warn "无法创建安全的 .ssh 目录。"; return 1; }
    touch "$path" || { warn "无法创建 authorized_keys。"; return 1; }
    chown "$uid:$gid" "$path" || { warn "无法设置 authorized_keys 所有者。"; return 1; }
    chmod 0600 "$path" || { warn "无法设置 authorized_keys 权限。"; return 1; }
    if [[ -s "$path" && -n "$(tail -c 1 "$path" 2>/dev/null || true)" ]]; then
      printf '\n' >>"$path" || { warn "无法补全 authorized_keys 的末尾换行。"; return 1; }
    fi
    printf '%s\n' "$key" >>"$path" || { warn "无法写入 authorized_keys。"; return 1; }
    grep -Fxq "$key" "$path" || { warn "SSH 公钥写入后验证失败。"; return 1; }
  fi
  audit "action=account-add-ssh-key user=$user path=$path"
  ui_success "SSH 公钥已添加"
}

account_create() {
  local user
  user="$(read_input "新用户名" "")"
  [[ -n "$user" ]] || return 0
  valid_username "$user" || { warn "用户名格式无效：仅允许小写字母、数字、下划线和短横线，且必须以字母或下划线开头。"; return 1; }
  account_exists "$user" && { warn "账户已存在：$user"; return 1; }
  command_exists adduser || { warn "系统缺少 adduser。"; return 1; }
  ui_panel_begin "创建计划"
  ui_panel_kv "用户名" "$user"
  ui_panel_kv "主目录" "/home/$user"
  ui_panel_kv "Shell" "/bin/bash"
  ui_panel_kv "密码登录" "默认禁用"
  ui_panel_end
  ui_note "账户创建后不会自动获得 sudo 权限；可以进入账户详情单独授权并添加 SSH 公钥。"
  confirm "创建账户 $user？" || return 0
  require_root
  run adduser --disabled-password --gecos "" --shell /bin/bash "$user" || {
    warn "账户创建命令执行失败。"
    return 1
  }
  if [[ "$DRY_RUN" -eq 0 ]]; then
    account_exists "$user" || { warn "账户创建后未通过验证。"; return 1; }
  fi
  audit "action=account-create user=$user"
  ui_success "账户 $user 已创建"
}

account_set_lock() {
  local user="$1" mode state label
  account_exists "$user" || { warn "账户不存在：$user"; return 1; }
  account_is_protected "$user" && { warn "拒绝修改 root、UID 0 或当前操作账户的锁定状态。"; return 1; }
  state="$(account_password_state "$user")"
  case "$mode" in
    lock)
      label="锁定"
      [[ "$state" != "locked" ]] || { warn "账户已经锁定。"; return 0; }
      ;;
    unlock)
      label="解锁"
      [[ "$state" == "locked" ]] || { warn "账户当前没有被锁定。"; return 0; }
      ;;
    *) return 1 ;;
  esac
  ui_note "该状态只控制密码认证，不会移除 SSH 公钥，也不会主动终止已经建立的会话。"
  confirm "$label 账户 $user？" || return 0
  require_root
  if [[ "$mode" == "lock" ]]; then
    run usermod -L "$user" || { warn "账户锁定命令执行失败。"; return 1; }
  else
    run usermod -U "$user" || { warn "账户解锁命令执行失败。"; return 1; }
  fi
  if [[ "$DRY_RUN" -eq 0 ]]; then
    state="$(account_password_state "$user")"
    if [[ "$mode" == "lock" && "$state" != "locked" ]]; then warn "账户锁定状态验证失败。"; return 1; fi
    if [[ "$mode" == "unlock" && "$state" == "locked" ]]; then warn "账户仍处于锁定状态。"; return 1; fi
  fi
  audit "action=account-$mode user=$user"
  ui_success "账户 $user 已$label"
}

account_sudo_member_count() {
  local user _password uid gid comment home shell count=0
  while IFS=: read -r user _password uid gid comment home shell; do
    if account_in_sudo "$user"; then count=$((count + 1)); fi
  done < <(getent passwd)
  printf '%s' "$count"
}

account_set_sudo() {
  local user="$1" mode count
  account_exists "$user" || { warn "账户不存在：$user"; return 1; }
  getent group sudo >/dev/null 2>&1 || { warn "系统没有 sudo 用户组。"; return 1; }
  command_exists gpasswd || { warn "系统缺少 gpasswd。"; return 1; }
  account_is_protected "$user" && { warn "拒绝修改 root、UID 0 或当前操作账户的 sudo 权限。"; return 1; }
  case "$mode" in
    grant)
      account_in_sudo "$user" && { warn "账户已经属于 sudo 组。"; return 0; }
      confirm "授予 $user sudo 管理权限？" || return 0
      ;;
    revoke)
      account_in_sudo "$user" || { warn "账户当前不属于 sudo 组。"; return 0; }
      count="$(account_sudo_member_count)"
      (( count > 1 )) || { warn "拒绝移除最后一个 sudo 组成员，避免失去管理入口。"; return 1; }
      ui_danger "移除后，该账户的新会话将不能通过 sudo 获取管理员权限。"
      confirm "移除 $user 的 sudo 管理权限？" || return 0
      ;;
    *) return 1 ;;
  esac
  require_root
  if [[ "$mode" == "grant" ]]; then
    run gpasswd -a "$user" sudo || { warn "sudo 授权命令执行失败。"; return 1; }
  else
    run gpasswd -d "$user" sudo || { warn "sudo 权限移除命令执行失败。"; return 1; }
  fi
  if [[ "$DRY_RUN" -eq 0 ]]; then
    if [[ "$mode" == "grant" ]]; then
      account_in_sudo "$user" || { warn "sudo 权限验证失败。"; return 1; }
    elif account_in_sudo "$user"; then
      warn "sudo 权限仍然存在。"
      return 1
    fi
  fi
  audit "action=account-sudo-$mode user=$user"
  ui_success "账户 $user 的 sudo 权限已更新"
}

system_account_select() {
  local user="$1" action uid gid comment home shell state sudo online keys
  account_exists "$user" || { warn "账户不存在：$user"; return 1; }
  while true; do
    uid="$(account_field "$user" 3)"
    gid="$(account_field "$user" 4)"
    comment="$(terminal_safe_text "$(account_field "$user" 5)")"
    home="$(terminal_safe_text "$(account_field "$user" 6)")"
    shell="$(terminal_safe_text "$(account_field "$user" 7)")"
    state="$(account_password_label "$user")"
    if account_in_sudo "$user"; then sudo="是"; else sudo="否"; fi
    online="$(account_online_count "$user")"
    keys="$(account_key_count "$user")"
    ui_page "账户管理 / $user" "身份、登录状态、SSH 公钥与权限"
    ui_panel_begin "账户信息"
    ui_panel_kv "UID / GID" "$uid / $gid"
    ui_panel_kv "说明" "${comment:-—}"
    ui_panel_kv "主目录" "$home"
    ui_panel_kv "Shell" "$shell"
    if [[ "$state" == "已锁定" ]]; then ui_panel_kv "认证状态" "● $state" "$YELLOW"; else ui_panel_kv "认证状态" "● $state" "$GREEN"; fi
    ui_panel_kv "sudo 权限" "$sudo"
    ui_panel_kv "在线会话" "$online"
    if [[ "$keys" =~ ^[0-9]+$ ]]; then ui_panel_kv "SSH 公钥" "$keys 把"; else ui_panel_kv "SSH 公钥" "$keys" "$YELLOW"; fi
    ui_panel_end
    ui_section "查看" "primary"
    ui_action_pair 1 "登录会话与历史" "action" 2 "SSH 公钥指纹" "action"
    ui_section "访问管理" "accent"
    ui_action 3 "添加 SSH 公钥" "success"
    if [[ "$state" == "已锁定" ]]; then
      ui_action_pair 4 "锁定密码（已锁定）" "muted" 5 "解锁密码认证" "warning"
    else
      ui_action_pair 4 "锁定密码认证" "danger" 5 "解锁密码（未锁定）" "muted"
    fi
    if [[ "$sudo" == "是" ]]; then
      ui_action_pair 6 "授予 sudo（已拥有）" "muted" 7 "移除 sudo" "danger"
    else
      ui_action_pair 6 "授予 sudo" "warning" 7 "移除 sudo（未拥有）" "muted"
    fi
    account_is_protected "$user" && ui_note "root、UID 0 和当前操作账户受保护，不能在此修改锁定状态或 sudo 权限。"
    ui_action 0 "返回" "muted"
    action="$(read_input "请选择" "0")"
    case "$action" in
      1) account_sessions "$user"; pause ;;
      2) account_keys_show "$user"; pause ;;
      3) account_key_add "$user" || true; pause ;;
      4) account_set_lock "$user" lock || true; pause ;;
      5) account_set_lock "$user" unlock || true; pause ;;
      6) account_set_sudo "$user" grant || true; pause ;;
      7) account_set_sudo "$user" revoke || true; pause ;;
      0) return 0 ;;
      *) warn "未知选项" ;;
    esac
  done
}

system_accounts_menu() {
  local action user
  while true; do
    ui_page "用户与账户" "本地账户、登录会话、SSH 公钥与 sudo 权限"
    ui_section "可管理账户" "primary"
    account_list
    ui_section "操作" "accent"
    ui_action_pair 1 "管理一个账户" "action" 2 "查看全部登录会话" "action"
    ui_action 3 "创建本地账户" "success" "默认禁用密码，不自动授予 sudo"
    ui_action 0 "返回" "muted"
    action="$(read_input "请选择" "0")"
    case "$action" in
      1)
        user="$(read_input "用户名" "")"
        [[ -n "$user" ]] || continue
        valid_username "$user" || { warn "用户名格式无效。"; pause; continue; }
        system_account_select "$user" || true
        ;;
      2) account_sessions; pause ;;
      3) account_create || true; pause ;;
      0) return 0 ;;
      *) warn "未知选项" ;;
    esac
  done
}
