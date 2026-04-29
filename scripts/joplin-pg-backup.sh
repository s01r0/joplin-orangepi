#!/usr/bin/env bash
set -euo pipefail

DB=joplindb
DBUSER=joplin
DBHOST=127.0.0.1
STATE_DIR=/var/lib/joplin-backup
STATE_FILE="${STATE_DIR}/state"
OUTDIR=/var/backups/joplin

STAMP="$(date +%F_%H%M%S)"
OUT="${OUTDIR}/joplindb_${STAMP}.sql.gz"

# -------- helpers --------
psql_q () {
  /usr/bin/psql -h "$DBHOST" -U "$DBUSER" -d "$DB" -Atc "$1"
}

# DBの変更チェック（stats比較）
READINGS="$(psql_q "SELECT (xact_commit + xact_rollback)::bigint,
                            (tup_inserted + tup_updated + tup_deleted)::bigint,
                            pg_database_size('${DB}')::bigint
                     FROM pg_stat_database WHERE datname='${DB}'")"

COMMITS="$(echo "$READINGS" | cut -f1)"
TUPS="$(echo "$READINGS" | cut -f2)"
SIZEB="$(echo "$READINGS" | cut -f3)"
CURRENT="${COMMITS}:${TUPS}:${SIZEB}"

if [[ -f "$STATE_FILE" ]]; then
  PREV="$(cat "$STATE_FILE" 2>/dev/null || true)"
  if [[ "$CURRENT" == "$PREV" ]]; then
    echo "No DB changes detected; skip backup."
    exit 0
  fi
fi

# バックアップ実行
/usr/bin/pg_dump -h "$DBHOST" -U "$DBUSER" -d "$DB" | /usr/bin/gzip -c > "$OUT"

# 直前のバックアップとMD5比較（内容が同一なら新ファイルを削除）
PREV_FILE=$(ls -t "$OUTDIR"/joplindb_*.sql.gz 2>/dev/null | grep -v "$OUT" | head -1 || true)
if [[ -n "$PREV_FILE" ]]; then
  NEW_MD5=$(md5sum "$OUT"       | cut -d' ' -f1)
  OLD_MD5=$(md5sum "$PREV_FILE" | cut -d' ' -f1)
  if [[ "$NEW_MD5" == "$OLD_MD5" ]]; then
    rm "$OUT"
    echo "Backup identical to previous (MD5 match); removed duplicate."
    exit 0
  fi
fi

echo "Backup written: $OUT"

# 古いバックアップ削除（14日超）
/usr/bin/find "$OUTDIR" -type f -name 'joplindb_*.sql.gz' -mtime +14 -delete

# 状態更新
echo "$CURRENT" > "$STATE_FILE"
