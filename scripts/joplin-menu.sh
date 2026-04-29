#!/usr/bin/env bash
set -euo pipefail

TITLE="Joplin Server 管理メニュー"

# サービス一覧（whiptail メニュー用: tag label の交互配列）
SYSTEMD_SERVICES=(
  "joplin-backup.timer"         "バックアップ           (毎日 3:00)"
  "joplin-backup-check.timer"   "バックアップ整合性チェック"
  "joplin-server-check.timer"   "Joplin Server 監視"
  "rclone-scansnap-sync.timer"  "ScanSnap rclone 同期  (2分おき)"
  "scansnap-to-joplin.timer"    "ScanSnap → Joplin 取り込み"
)

ALL_LOG_SERVICES=(
  "docker:joplin"               "Joplin Server (Docker)"
  "joplin-backup.timer"         "バックアップ"
  "joplin-backup-check.timer"   "バックアップ整合性チェック"
  "joplin-server-check.timer"   "Joplin Server 監視"
  "rclone-scansnap-sync.timer"  "ScanSnap rclone 同期"
  "scansnap-to-joplin.timer"    "ScanSnap → Joplin 取り込み"
)

# --- ステータス表示 ---
show_status() {
  local output=""

  # Docker コンテナ
  if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^joplin$"; then
    output+="[稼働中] Docker: joplin\n"
  else
    output+="[停止  ] Docker: joplin\n"
  fi
  output+="\n"

  # systemd タイマー/サービス
  local tags=()
  for ((i=0; i<${#SYSTEMD_SERVICES[@]}; i+=2)); do
    tags+=("${SYSTEMD_SERVICES[$i]}")
  done

  for svc in "${tags[@]}"; do
    local active
    active=$(systemctl is-active "$svc" 2>/dev/null || echo "inactive")
    local icon
    case "$active" in
      active)   icon="[稼働中]" ;;
      inactive) icon="[停止  ]" ;;
      failed)   icon="[エラー]" ;;
      *)        icon="[不明  ]" ;;
    esac
    output+="${icon} ${svc}\n"
  done

  # 最終バックアップ
  output+="\n"
  local last_bk
  last_bk=$(ls -t /var/backups/joplin/*.gz 2>/dev/null | head -1 || echo "(なし)")
  output+="最終バックアップ: $(basename "$last_bk" 2>/dev/null || echo "(なし)")"

  whiptail --title "サーバー状態" --msgbox "$(printf '%b' "$output")" 22 65
}

# --- サービス操作 ---
service_ops() {
  local svc
  svc=$(whiptail --title "サービス操作" --menu "操作するサービスを選択:" 20 65 8 \
    "docker:joplin-server"       "Joplin Server (Docker)" \
    "${SYSTEMD_SERVICES[@]}" \
    3>&1 1>&2 2>&3) || return 0

  local action
  action=$(whiptail --title "操作: $svc" --menu "操作を選択:" 14 60 5 \
    "start"   "起動" \
    "stop"    "停止" \
    "restart" "再起動" \
    "status"  "状態確認" \
    3>&1 1>&2 2>&3) || return 0

  local out
  if [[ "$svc" == docker:* ]]; then
    local container="${svc#docker:}"
    if [ "$action" = "status" ]; then
      out=$(docker inspect --format \
        'Status: {{.State.Status}}  Started: {{.State.StartedAt}}' \
        "$container" 2>&1 || true)
      out+=$'\n\n'"$(docker logs --tail 30 "$container" 2>&1 || true)"
    else
      out=$(docker "$action" "$container" 2>&1 || true)
    fi
  else
    if [ "$action" = "status" ]; then
      out=$(systemctl status "$svc" --no-pager 2>&1 || true)
    else
      sudo systemctl "$action" "$svc" 2>&1 || true
      out="${svc} を ${action} しました"
    fi
  fi

  whiptail --title "結果: $svc" --scrolltext --msgbox "$out" 24 80
}

# --- ログ閲覧 ---
show_log() {
  local svc
  svc=$(whiptail --title "ログ閲覧" --menu "ログを表示するサービスを選択:" 20 65 8 \
    "${ALL_LOG_SERVICES[@]}" \
    3>&1 1>&2 2>&3) || return 0

  local out
  if [[ "$svc" == docker:* ]]; then
    local container="${svc#docker:}"
    out=$(docker logs --tail 50 "$container" 2>&1 || true)
  else
    out=$(journalctl -u "$svc" -n 50 --no-pager 2>&1 || true)
  fi

  whiptail --title "ログ: $svc" --scrolltext --msgbox "$out" 30 100
}

# --- メインループ ---
while true; do
  choice=$(whiptail --title "$TITLE" --menu "操作を選択してください:" 14 60 5 \
    "1" "サーバー状態確認" \
    "2" "サービス操作" \
    "3" "ログ閲覧" \
    "4" "終了" \
    3>&1 1>&2 2>&3) || break

  case "$choice" in
    1) show_status ;;
    2) service_ops ;;
    3) show_log ;;
    4) break ;;
  esac
done
