#!/bin/bash
# ============================================================
# addon/dropbear-fastkick.sh
# Menjaga jalur nTLS (Dropbear, port 80/8880/8080/2080/2082).
# Dropbear tidak pakai PAM, jadi limit di sini REAKTIF (bukan
# preventive kayak OpenSSH): poll 5 detik + cooldown 30 detik
# per user, HANYA menghitung/mematikan proses dropbear (tidak
# pernah menyentuh sesi OpenSSH milik user yang sama).
#
# Dijalankan sebagai systemd service (lihat dropbear-fastkick.service),
# bukan cron, supaya polling 5 detik gak spawn proses baru tiap kali.
# ============================================================
SCRIPT_DIR="/etc/vpn-script"
source "$SCRIPT_DIR/lib.sh"

STATE_DIR="$SCRIPT_DIR/.dropbear-fastkick-state"
mkdir -p "$STATE_DIR"
POLL=5
COOLDOWN=30

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }
log "dropbear-fastkick dimulai (poll=${POLL}s, cooldown=${COOLDOWN}s)"

while true; do
    while IFS='|' read -r user pass exp created limit quota; do
        [[ -z "$user" ]] && continue
        limit="${limit:-$SESSION_LIMIT_DEFAULT}"
        [[ "$limit" =~ ^[0-9]+$ ]] || continue
        [[ "$limit" -eq 0 ]] && continue

        # Hanya hitung proses DROPBEAR milik user ini (bukan sshd/OpenSSH)
        count=$(pgrep -u "$user" -x dropbear 2>/dev/null | wc -l)
        [[ "$count" -le "$limit" ]] && continue

        state_file="$STATE_DIR/$user"
        last=$(cat "$state_file" 2>/dev/null || echo 0)
        now=$(date +%s)
        (( now - last < COOLDOWN )) && continue

        log "$user: dropbear=$count > limit=$limit -> kill sesi dropbear"
        pkill -9 -u "$user" -x dropbear 2>/dev/null
        echo "$now" > "$state_file"

        tg_notify "🚫 <b>Limit Device Terlampaui (nTLS/Dropbear)</b>

Username: <code>$user</code>
Sesi Dropbear aktif: <code>$count</code> (limit: <code>$limit</code>)
Aksi: sesi nTLS diputus, user perlu reconnect" "limit"
    done < <(list_ssh)
    sleep "$POLL"
done
