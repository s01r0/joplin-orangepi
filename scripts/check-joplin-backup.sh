#!/usr/bin/env bash
# check-joplin-backup.sh
# Joplin PostgreSQL バックアップの定例実行を総合チェック
# - systemd timer / service 稼働確認
# - 直近24hの実行ログとエラー検出
# - 最新バックアップファイルの存在 / 日付 / サイズ / gzip整合性
# 失敗時は非ゼロ終了で終了

set -euo pipefail

SERVICE="joplin-backup.service"
TIMER="joplin-backup.timer"
BACKUP_DIR="/var/backups"
FILE_PREFIX="joplindb_"
FRESH_HOURS=36          # 36時間以内を「新しい」と判定
MIN_SIZE_BYTES=$((100*1024))  # 100KB未満は異常扱い（環境に合わせて調整可）

RED=$'\e[31m'; GREEN=$'\e[32m'; YELLOW=$'\e[33m'; BOLD=$'\e[1m'; NC=$'\e[0m'
fail=false

section () { echo; echo "${BOLD}== $1 ==${NC}"; }
ok ()    { echo "  ${GREEN}[OK]${NC} $*"; }
warn ()  { echo "  ${YELLOW}[WARN]${NC} $*"; }
error () { echo "  ${RED}[FAIL]${NC} $*"; fail=true; }

# 1) systemd timer / service 確認
section "systemd status"
if systemctl is-enabled --quiet "$TIMER"; then
  ok "timer enabled: $TIMER"
else
  error "timer NOT enabled: $TIMER"
fi

if systemctl is-active --quiet "$TIMER"; then
  ok "timer active: $TIMER"
else
  error "timer NOT active: $TIMER"
fi

LIST=$(systemctl list-timers --all | grep -E "$TIMER" || true)
if [[ -n "${LIST}" ]]; then
  ok "list-timers: ${LIST}"
else
  warn "list-timers に $TIMER が見つかりませんでした"
fi

# 2) サービス直近の実行結果
section "service last result"
RESULT=$(systemctl show "$SERVICE" -p Result --value 2>/dev/null || true)
EXITC=$(systemctl show "$SERVICE" -p ExecMainStatus --value 2>/dev/null || true)
STATE=$(systemctl is-active "$SERVICE" 2>/dev/null || true)
ok "service active state: ${STATE:-unknown}"
if [[ "$RESULT" == "success" || "$EXITC" == "0" ]]; then
  ok "last result: Result=${RESULT:-n/a} ExecMainStatus=${EXITC:-n/a}"
else
  warn "last result: Result=${RESULT:-n/a} ExecMainStatus=${EXITC:-n/a}（直近で失敗の可能性）"
fi

# 3) 直近24時間ログ・エラー検出
section "journal logs (last 24h)"
journalctl -u "$SERVICE" --since "24 hours ago" --no-pager || true

ERRS=$(journalctl -u "$SERVICE" --since "24 hours ago" --no-pager \
  | grep -i -E "error|failed|permission denied|no such file|could not|fatal" || true)
if [[ -n "$ERRS" ]]; then
  error "journalにエラーらしき出力を検出"
else
  ok "journalに顕著なエラーは見当たりません"
fi

# 4) 最新バックアップファイル確認
section "backup file checks"
LATEST=$(ls -1t "${BACKUP_DIR}/${FILE_PREFIX}"*.sql.gz 2>/dev/null | head -n1 || true)
if [[ -z "${LATEST}" ]]; then
  error "バックアップファイルが見つかりません: ${BACKUP_DIR}/${FILE_PREFIX}*.sql.gz"
else
  ok "latest file: ${LATEST}"

  NOW=$(date +%s)
  MTIME=$(stat -c %Y "$LATEST")
  AGE_SEC=$((NOW - MTIME))
  AGE_H=$((AGE_SEC / 3600))
  if (( AGE_SEC <= FRESH_HOURS*3600 )); then
    ok "file is fresh: 約${AGE_H}時間前に作成"
  else
    error "file is stale: 約${AGE_H}時間前に作成（閾値 ${FRESH_HOURS}h 超過）"
  fi

  SIZE=$(stat -c %s "$LATEST")
  if (( SIZE >= MIN_SIZE_BYTES )); then
    ok "size: $SIZE bytes"
  else
    error "size too small: $SIZE bytes (< ${MIN_SIZE_BYTES})"
  fi

  if gzip -t "$LATEST" 2>/dev/null; then
    ok "gzip integrity: PASS"
  else
    error "gzip integrity: FAIL"
  fi
fi

section "summary"
if $fail; then
  echo "${RED}${BOLD}バックアップ確認: NG（要確認）${NC}"
  exit 1
else
  echo "${GREEN}${BOLD}バックアップ確認: OK${NC}"
  exit 0
fi
