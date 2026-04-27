#!/usr/bin/env bash
set -euo pipefail

DB=joplindb
DBUSER=joplin
DBHOST=127.0.0.1
STATE_DIR=/var/lib/joplin-backup
STATE_FILE="${STATE_DIR}/state"
LASTFORCE_FILE="${STATE_DIR}/last_forced_backup"
OUTDIR=/var/backups/joplin

STAMP="$(date +%F_%H%M%S)"
OUT="${OUTDIR}/joplindb_${STAMP}.sql.gz"

# -------- helpers --------
psql_q () {
  /usr/bin/psql -h "$DBHOST" -U "$DBUSER" -d "$DB" -Atc "$1"
}

# 取得：累積カウンタとサイズ（タブ区切り）
READINGS="$(psql_q "SELECT (xact_commit + xact_rollback)::bigint,
                            (tup_inserted + tup_updated + tup_deleted)::bigint,
                            pg_database_size('${DB}')::bigint
                     FROM pg_stat_database WHERE datname='${DB}'")"

COMMITS="$(echo "$READINGS" | cut -f1)"
TUPS="$(echo "$READINGS" | cut -f2)"
SIZEB="$(echo "$READINGS" | cut -f3)"

CURRENT="${COMMITS}:${TUPS}:${SIZEB}"

# 保険：最終強制バックアップから7日以上なら強制バックアップ
force_backup=false
if [[ -f "$LASTFORCE_FILE" ]]; then
  if [[ $(find "$LASTFORCE_FILE" -mtime +6 -print -quit) ]]; then
    force_backup=true
  fi
else
  # 初回は強制
  force_backup=true
fi

# 変更判定
changed=true
if [[ -f "$STATE_FILE" ]]; then
  PREV="$(cat "$STATE_FILE" 2>/dev/null || true)"
  if [[ "$CURRENT" == "$PREV" ]] && [[ $force_backup == false ]]; then
    changed=false
  fi
fi

if [[ $changed == false ]]; then
  echo "No DB changes detected; skip backup."
  exit 0
fi

# バックアップ実行
/usr/bin/pg_dump -h "$DBHOST" -U "$DBUSER" -d "$DB" | /usr/bin/gzip -c > "$OUT"
echo "Backup written: $OUT"

# 古いバックアップ削除（14日超）
/usr/bin/find "$OUTDIR" -type f -name 'joplindb_*.sql.gz' -mtime +14 -delete

# 状態更新
echo "$CURRENT" > "$STATE_FILE"

# 今回が強制バックアップなら印を更新、または初回印を作成
date -u +%s > "$LASTFORCE_FILE"
