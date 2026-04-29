#!/usr/bin/env bash
set -euo pipefail

SERVER_IP="${SERVER_IP:?SERVER_IP environment variable is not set}"
BASE="http://${SERVER_IP}:22300"
URL="${BASE}/"

code=$(curl -sS -H "Origin: ${BASE}" -o /dev/null -w '%{http_code}' "${URL}" || echo 000)

if [[ "$code" =~ ^(200|302|401|403)$ ]]; then
  echo "[OK] Joplin Server HTTP ${code}"
  exit 0
else
  echo "[ERROR] Joplin Server HTTP ${code} - restarting..."
  docker restart joplin-server || true

  # 再確認
  sleep 10
  code2=$(curl -sS -H "Origin: ${BASE}" -o /dev/null -w '%{http_code}' "${URL}" || echo 000)
  if [[ "$code2" =~ ^(200|302|401|403)$ ]]; then
    echo "[RECOVERED] Joplin Server HTTP ${code2}"
    exit 0
  else
    echo "[FATAL] Joplin Server still HTTP ${code2} after restart"
    exit 1
  fi
fi
