#!/usr/bin/env bash
# OrangePi5 Joplin Server 一括復旧スクリプト
# 新しいOrangePi5にSSHして実行する
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"

log()  { printf '\n\e[1;32m[%s] %s\e[0m\n' "$(date '+%H:%M:%S')" "$*"; }
fail() { printf '\e[1;31m[ERROR] %s\e[0m\n' "$*" >&2; exit 1; }

# --- 前提確認 ---
[[ "$(id -u)" -ne 0 ]] && fail "sudo で実行してください: sudo bash restore.sh"

log "1/6 パッケージ更新"
apt update -qq && apt upgrade -y -qq

log "2/6 必要パッケージインストール"
apt install -y -qq \
  build-essential git curl wget \
  postgresql \
  ca-certificates gnupg lsb-release

log "3/6 PostgreSQL セットアップ"
systemctl enable --now postgresql

sudo -u postgres psql -c "CREATE ROLE joplin WITH LOGIN PASSWORD '${POSTGRES_PASSWORD:?POSTGRES_PASSWORD を設定してください}';" 2>/dev/null || echo "  ロールは既に存在します（スキップ）"
sudo -u postgres psql -c "CREATE DATABASE joplindb OWNER joplin;" 2>/dev/null || echo "  DBは既に存在します（スキップ）"
sudo -u postgres psql -c "ALTER ROLE joplin SET client_encoding TO 'UTF8';"
sudo -u postgres psql -c "ALTER ROLE joplin SET default_transaction_isolation TO 'read committed';"
sudo -u postgres psql -c "ALTER ROLE joplin SET timezone TO 'UTC';"

log "4/6 Docker インストール"
if ! command -v docker &>/dev/null; then
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/trusted.gpg.d/docker.gpg
  echo "deb [arch=arm64] https://download.docker.com/linux/ubuntu jammy stable" \
    > /etc/apt/sources.list.d/docker.list
  apt update -qq
  apt install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  systemctl enable --now docker
  usermod -aG docker ubuntu
else
  echo "  Docker は既にインストール済み（スキップ）"
fi

log "5/6 systemd ユニット配置"
install -m 0755 -o root -g root "${REPO_DIR}/scripts/joplin-pg-backup.sh" /usr/local/sbin/
install -m 0644 -o root -g root "${REPO_DIR}/systemd/joplin-backup.service" /etc/systemd/system/
install -m 0644 -o root -g root "${REPO_DIR}/systemd/joplin-backup.timer"   /etc/systemd/system/

mkdir -p /var/backups/joplin /var/lib/joplin-backup
chown postgres:postgres /var/backups/joplin /var/lib/joplin-backup

systemctl daemon-reload
systemctl enable --now joplin-backup.timer

log "6/6 Joplin Server コンテナ起動"
bash "${REPO_DIR}/docker/joplin-run.sh"

log "復旧完了！"
echo "  Joplin: http://\$(hostname -I | awk '{print \$1}'):22300"
echo "  バックアップ確認: systemctl list-timers | grep joplin"
