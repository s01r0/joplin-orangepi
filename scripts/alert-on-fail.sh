#!/usr/bin/env bash
# alert-on-fail.sh
# コマンドを実行し、失敗時に Gmail で通知する汎用ラッパー
# 使い方: alert-on-fail.sh <command> [args...]
set -euo pipefail

MAIL_TO="s01r0.fjmt@gmail.com"
MSMTPRC="/home/ubuntu/.msmtprc"
SUBJECT_PREFIX="[Joplin監視]"

if [ "$#" -lt 1 ]; then
  echo "Usage: $0 <command...>" >&2
  exit 64
fi

OUT="$(mktemp)"
ERR="$(mktemp)"
set +e
"$@" >"$OUT" 2>"$ERR"
rc=$?
set -e

if [ $rc -ne 0 ]; then
  {
    echo "To: ${MAIL_TO}"
    echo "From: ${MAIL_TO}"
    echo "Subject: ${SUBJECT_PREFIX} 失敗: $* (rc=${rc})"
    echo "Content-Type: text/plain; charset=UTF-8"
    echo
    echo "host: $(hostname)"
    echo "when: $(date '+%F %T %Z')"
    echo "cmd : $*"
    echo "rc  : ${rc}"
    echo
    echo "---- STDOUT ----"
    sed -e 's/\x1b\[[0-9;]*m//g' "$OUT" || true
    echo
    echo "---- STDERR ----"
    sed -e 's/\x1b\[[0-9;]*m//g' "$ERR" || true
  } | msmtp -C "${MSMTPRC}" -a gmail -t
fi

rm -f "$OUT" "$ERR"
exit $rc
