# CHANGELOG - v1.0.6 (SSH-WS nTLS port 80 path "/" -> OpenSSH)

## Perbaikan
- `install.sh` & `lib.sh` (`regenerate_nginx_conf`): `location /` di blok port 80 sekarang
  meneruskan WebSocket ke `ws-openssh` (2093 -> OpenSSH). Sebelumnya hanya redirect 301 ke HTTPS,
  sehingga payload bertipe `BMOVE / [protocol] ... Upgrade: websocket` tidak pernah sampai ke SSH.
  Request tanpa `Upgrade: websocket` tetap di-redirect ke HTTPS.
- `addon/install-sshws.sh` (`ws-openssh`): data `[split]` berawalan `HTTP/` dibuang sebelum
  diteruskan ke sshd (sshd menolak baris selain `SSH-` di awal: "invalid protocol identifier").

## Tidak berubah
- Port 8880/8080/2080/2082 dan 443, Xray, Dropbear (`ws-dropbear`), Stunnel/HAProxy.

## Dokumentasi
- `DEPLOY.md`: arsitektur WS TLS 443 dikoreksi sesuai konfigurasi sebenarnya
  (`/ssh-ws` -> Dropbear, `/ssh-ws-ssh` -> OpenSSH) + catatan alur port 80 path `/`.
