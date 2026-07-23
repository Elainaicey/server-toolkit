#!/usr/bin/env bash

security_certificate_days_left() {
  local not_after="$1" now="${2:-}" expiry_epoch delta
  [[ -n "$now" ]] || now="$(date +%s)"
  expiry_epoch="$(date -d "$not_after" +%s 2>/dev/null)" || return 1
  delta=$((expiry_epoch - now))
  if (( delta >= 0 )); then
    printf '%s' "$(((delta + 86399) / 86400))"
  else
    printf '%s' "$(((delta - 86399) / 86400))"
  fi
}

security_tls_inspect() {
  local target port endpoint pem certificate not_after days_left identity_check
  ui_hint "目标可填写域名、IPv4 或 IPv6；随后输入 1-65535 的 TLS 端口。"
  target="$(read_input "域名或 IP" "github.com")"
  valid_network_target "$target" || { warn "目标格式无效。"; return 1; }
  port="$(read_input "TLS 端口" "443")"
  valid_port "$port" || { warn "端口无效。"; return 1; }
  command_exists openssl || { warn "未安装 openssl。"; return 1; }
  command_exists timeout || { warn "缺少 timeout 命令。"; return 1; }
  endpoint="$target:$port"
  if [[ "$target" == *:* ]]; then endpoint="[$target]:$port"; fi
  ui_page "TLS 证书检查" "$target:$port"
  pem="$(timeout 12 openssl s_client -servername "$target" -connect "$endpoint" </dev/null 2>/dev/null || true)"
  certificate="$(openssl x509 -noout -subject -issuer -serial -dates -fingerprint -sha256 2>/dev/null <<<"$pem" || true)"
  [[ -n "$certificate" ]] || { warn "未能取得有效证书。"; return 1; }
  printf '%s\n' "$certificate"
  ui_section "有效期与身份" "accent"
  not_after="$(openssl x509 -noout -enddate 2>/dev/null <<<"$pem" | sed 's/^notAfter=//' || true)"
  if [[ -n "$not_after" ]] && days_left="$(security_certificate_days_left "$not_after")"; then
    if (( days_left < 0 )); then
      ui_check fail "证书已经过期 $((-days_left)) 天"
    elif (( days_left < 14 )); then
      ui_check fail "证书将在 $days_left 天内过期"
    elif (( days_left < 30 )); then
      ui_check warn "证书将在 $days_left 天后过期"
    else
      ui_check pass "证书剩余有效期 $days_left 天"
    fi
  else
    ui_check warn "无法计算证书剩余有效期"
  fi
  if [[ "$target" == *:* || "$target" =~ ^[0-9]+([.][0-9]+){3}$ ]]; then
    identity_check="$(openssl x509 -noout -checkip "$target" 2>/dev/null <<<"$pem" || true)"
  else
    identity_check="$(openssl x509 -noout -checkhost "$target" 2>/dev/null <<<"$pem" || true)"
  fi
  if [[ "$identity_check" == *"does match certificate"* ]]; then
    ui_check pass "证书身份与 $target 匹配"
  else
    ui_check fail "证书身份与 $target 不匹配"
  fi
  ui_section "证书主机名" "primary"
  openssl x509 -noout -ext subjectAltName 2>/dev/null <<<"$pem" || true
}
