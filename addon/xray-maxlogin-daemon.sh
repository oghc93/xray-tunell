#!/bin/bash
# ============================================================
# addon/xray-maxlogin-daemon.sh
# Pengganti addon/xray-device-limiter.sh lama (cron 2 menit,
# kick semua device sekaligus). Sekarang: poll 5 detik + cooldown
# 30 detik per akun, dijalankan sebagai systemd service (lihat
# xray-maxlogin.service), bukan cron.
# ============================================================
SCRIPT_DIR="/etc/vpn-script"
source "$SCRIPT_DIR/lib.sh"

POLL_INTERVAL=5
COOLDOWN=30
STATE_DIR="$SCRIPT_DIR/.maxlogin-daemon-state"
mkdir -p "$STATE_DIR"

command -v xray >/dev/null 2>&1 || { echo "[FATAL] xray tidak ditemukan"; exit 1; }
ensure_xray_stats_api || echo "[WARN] gagal memastikan Stats API aktif, lanjut coba jalan..."

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

reset_vmess() {
  local email="$1" uuid="$2" tmp
  tmp=$(mktemp)
  jq --arg email "$email" \
    '(.inbounds[] | select(.tag | startswith("vmess")) | .settings.clients) |= map(select(.email != $email))' \
    "$XRAY_CONFIG" > "$tmp" && mv "$tmp" "$XRAY_CONFIG"
  jq --arg uuid "$uuid" --arg email "$email" \
    '(.inbounds[] | select(.tag == "vmess-ws-tls" or .tag == "vmess-ws-ntls") | .settings.clients) += [{"id": $uuid, "alterId": 0, "email": $email}]' \
    "$XRAY_CONFIG" > /tmp/xr.$$ && mv /tmp/xr.$$ "$XRAY_CONFIG"
}
reset_vless() {
  local email="$1" uuid="$2" tmp
  tmp=$(mktemp)
  jq --arg email "$email" \
    '(.inbounds[] | select(.tag | startswith("vless")) | .settings.clients) |= map(select(.email != $email))' \
    "$XRAY_CONFIG" > "$tmp" && mv "$tmp" "$XRAY_CONFIG"
  jq --arg uuid "$uuid" --arg email "$email" \
    '(.inbounds[] | select(.tag == "vless-ws-tls" or .tag == "vless-ws-ntls" or .tag == "vless-grpc-tls") | .settings.clients) += [{"id": $uuid, "email": $email, "flow": ""}]' \
    "$XRAY_CONFIG" > /tmp/xr.$$ && mv /tmp/xr.$$ "$XRAY_CONFIG"
}
reset_trojan() {
  local email="$1" pass="$2" tmp
  tmp=$(mktemp)
  jq --arg email "$email" \
    '(.inbounds[] | select(.tag | startswith("trojan")) | .settings.clients) |= map(select(.email != $email))' \
    "$XRAY_CONFIG" > "$tmp" && mv "$tmp" "$XRAY_CONFIG"
  jq --arg pass "$pass" --arg email "$email" \
    '(.inbounds[] | select(.tag | startswith("trojan")) | .settings.clients) += [{"password": $pass, "email": $email}]' \
    "$XRAY_CONFIG" > /tmp/xr.$$ && mv /tmp/xr.$$ "$XRAY_CONFIG"
}
reset_ss() {
  local email="$1" pass="$2" method="$3" tmp
  tmp=$(mktemp)
  jq --arg email "$email" \
    '(.inbounds[] | select(.tag | startswith("ss-")) | .settings.clients) |= map(select(.email != $email))' \
    "$XRAY_CONFIG" > "$tmp" && mv "$tmp" "$XRAY_CONFIG"
  jq --arg pass "$pass" --arg method "$method" --arg email "$email" \
    '(.inbounds[] | select(.tag | startswith("ss-")) | .settings.clients) += [{"method": $method, "password": $pass, "email": $email}]' \
    "$XRAY_CONFIG" > /tmp/xr.$$ && mv /tmp/xr.$$ "$XRAY_CONFIG"
}

enforce() {
  local proto="$1" email="$2" limit="$3"; shift 3
  [[ "$limit" =~ ^[0-9]+$ ]] || return
  [[ "$limit" -eq 0 ]] && return
  local online; online=$(get_xray_user_online "$email")
  [[ "$online" =~ ^[0-9]+$ ]] || return
  (( online <= limit )) && return
  local state_file="$STATE_DIR/${proto}_${email}" last now
  last=$(cat "$state_file" 2>/dev/null || echo 0); now=$(date +%s)
  (( now - last < COOLDOWN )) && return
  log "$email ($proto): online=$online > limit=$limit -> reset"
  case "$proto" in
    vmess)  reset_vmess  "$email" "$1" ;;
    vless)  reset_vless  "$email" "$1" ;;
    trojan) reset_trojan "$email" "$1" ;;
    ss)     reset_ss     "$email" "$1" "$2" ;;
  esac
  echo "$now" > "$state_file"
  tg_notify "🚫 <b>Limit Device Terlampaui</b>

Protokol: <code>$proto</code>
Username: <code>$email</code>
Device aktif: <code>$online</code> (limit: <code>$limit</code>)
Aksi: sesi diputus, user perlu reconnect" "limit"
}

log "xray-maxlogin-daemon dimulai (poll=${POLL_INTERVAL}s, cooldown=${COOLDOWN}s)"
while true; do
  while IFS='|' read -r user uuid exp created ip_limit quota_mb; do [[ -z "$user" ]] && continue; enforce vmess "$user" "${ip_limit:-$IP_LIMIT_DEFAULT}" "$uuid"; done < <(list_vmess)
  while IFS='|' read -r user uuid exp created ip_limit quota_mb; do [[ -z "$user" ]] && continue; enforce vless "$user" "${ip_limit:-$IP_LIMIT_DEFAULT}" "$uuid"; done < <(list_vless)
  while IFS='|' read -r user pass exp created ip_limit quota_mb; do [[ -z "$user" ]] && continue; enforce trojan "$user" "${ip_limit:-$IP_LIMIT_DEFAULT}" "$pass"; done < <(list_trojan)
  while IFS='|' read -r user pass method exp created ip_limit quota_mb; do [[ -z "$user" ]] && continue; enforce ss "$user" "${ip_limit:-$IP_LIMIT_DEFAULT}" "$pass" "$method"; done < <(list_ss)
  systemctl reload xray 2>/dev/null || systemctl restart xray 2>/dev/null
  sleep "$POLL_INTERVAL"
done
