#!/usr/bin/env bash
# Joplin Server コンテナ起動スクリプト
# 実行前に .env を用意すること（.env.example を参照）
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "ERROR: $ENV_FILE が見つかりません。.env.example をコピーして編集してください。"
  exit 1
fi

# shellcheck source=/dev/null
source "$ENV_FILE"

sudo docker pull joplin/server:latest

sudo docker run -d --name joplin-server \
  -e APP_PORT=22300 \
  -e APP_BASE_URL="http://${SERVER_IP}:22300" \
  -e POSTGRES_PASSWORD="${POSTGRES_PASSWORD}" \
  -e POSTGRES_DATABASE=joplindb \
  -e POSTGRES_USER=joplin \
  -e POSTGRES_PORT=5432 \
  -e POSTGRES_HOST="${SERVER_IP}" \
  -p 22300:22300 \
  --restart unless-stopped \
  joplin/server:latest

echo "Joplin Server 起動完了: http://${SERVER_IP}:22300"
