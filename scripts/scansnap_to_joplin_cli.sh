#!/usr/bin/env bash
#==============================================================
#  ScanSnap -> Joplin (CLI)
#  - INBOX の PDF を Joplin にノートとして作成 & 添付して取り込み
#  - 仮タイトルでノート作成 -> NOTE_ID 取得 -> 添付 -> 本タイトルに改名
#  - 成功したら done / 失敗したら error へ移動
#  - 終了時に joplin sync（失敗しても続行）
#==============================================================

set -Eeuo pipefail
export LANG=C.UTF-8
export LC_ALL=C

#===== 設定 ===============================================
JOPLIN=/usr/local/bin/joplin

INBOX=/srv/scansnap/inbox
DONE=/srv/scansnap/done
ERR=/srv/scansnap/error
WORK=/srv/scansnap/processing
LOG=/srv/scansnap/logs/scansnap_to_joplin.log
LOCK=/srv/scansnap/scansnap_to_joplin.lock

BOOK=scansnap_inbox
NOTE_BODY_PREFIX="Scanned via ScanSnap."
#==========================================================

log() {
  printf '[%s] %s\n' "$(date '+%F %T')" "$*" | tee -a "$LOG"
}

note_id_from_title() {
  local t="$1"
  LC_ALL=C $JOPLIN ls --long --sort created_time --reverse -n 3000 2>/dev/null \
  | awk -v t="$t" '{
      id=$1; title="";
      for(i=4;i<=NF;i++) title = title (i==4?"":" ") $i;
      sub(/ \([0-9a-f]{5}\)$/,"",title);
      if(title==t){ print id; exit }
    }'
}

mkdir -p "$INBOX" "$DONE" "$ERR" "$WORK" "$(dirname "$LOG")"

# 多重起動防止
exec 9>"$LOCK"
if ! flock -n 9; then
  log "INFO: another instance is running, exit."
  exit 0
fi
trap 'flock -u 9 || true' EXIT

# ノートブック選択（なければ作成）
if ! "$JOPLIN" use "$BOOK" >/dev/null 2>&1; then
  "$JOPLIN" mkbook "$BOOK" >/dev/null 2>&1 || { log "ERROR: cannot create notebook: $BOOK"; exit 1; }
  "$JOPLIN" use "$BOOK" >/dev/null 2>&1 || { log "ERROR: cannot select book: $BOOK"; exit 1; }
fi
log "use notebook: $BOOK"

mapfile -d '' -t pdfs < <(find "$INBOX" -maxdepth 1 -type f -iname '*.pdf' -print0 | sort -z)
if ((${#pdfs[@]} == 0)); then
  log "No PDFs to process."; exit 0
fi

for f in "${pdfs[@]}"; do
  base="$(basename "$f")"
  real_title="${base%.pdf}"
  ts="$(date +%y%m%d_%H%M)"
  tmp="tmp__${ts}_$$"

  # 1) 仮タイトルでノート作成（最大3回リトライ）
  ok=no
  for _ in 1 2 3; do
    if "$JOPLIN" mknote "$tmp" --body "$NOTE_BODY_PREFIX $real_title" >/dev/null 2>&1; then
      ok=yes; break
    fi
    sleep 0.2
  done
  if [[ "$ok" != yes ]]; then
    log "ERROR: note create failed: $base"
    mv -f "$f" "$ERR" || true
    continue
  fi

  log "processing: $base"

  # 2) NOTE_ID 取得（最大10回リトライ）
  NOTE_ID=""
  for _ in $(seq 1 20); do
    NOTE_ID="$(note_id_from_title "$tmp")"
    [ -n "$NOTE_ID" ] && break
    sleep 0.5
  done

  if [ -z "$NOTE_ID" ]; then
    log "ERROR: cannot get note id for tmp='$tmp'"
    mv -f "$f" "$ERR/" || true
    continue
  fi

  # 3) PDF 添付（最大3回リトライ）
  ok=no
  for _ in 1 2 3; do
    if "$JOPLIN" attach "$NOTE_ID" "$f" >/dev/null 2>&1; then ok=yes; break; fi
    sleep 0.2
  done
  if [ "$ok" != yes ]; then
    log "ERROR: attach failed (id=$NOTE_ID): $base"
    mv -f "$f" "$ERR/" || true
    continue
  fi

  # 4) 本タイトルに改名
  "$JOPLIN" rename "$NOTE_ID" "$real_title" >/dev/null 2>&1 || true
  log "OK: $base -> note '$real_title' (id=$NOTE_ID)"
  mv -f "$f" "$DONE/" || true
done

# 同期（失敗しても続行）
"$JOPLIN" sync --log-level info >>"$LOG" 2>&1 || true
