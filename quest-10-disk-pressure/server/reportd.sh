#!/bin/bash
# 5秒ごとにレポートを1件書き出し、処理ログを追記する。
# 両方が書けている間だけ成果物(flag.txt)を置く。
# FLAGはこのプロセスのメモリ上にしか存在しない。ディスクには健全なときだけ現れる。
LOGDIR=/var/log/reportd
REPORTS=$LOGDIR/reports
STATE=/var/lib/reportd

FLAG="FLAG{$(head -c 16 /dev/urandom | md5sum | cut -d' ' -f1)}"
mkdir -p "$STATE"
mkdir -p "$REPORTS" 2>/dev/null

# 一般的なデーモンと同じく、処理ログはfdを掴みっぱなしにする
exec 3>>"$LOGDIR/app.log"

while true; do
  ok=1

  # レポート本体(1件ぶん)を新規ファイルとして書き出す
  if ! head -c 65536 /dev/zero | tr '\0' 'x' > "$REPORTS/report-$(date +%s).txt" 2>/dev/null; then
    ok=0
  fi

  # 処理ログを追記する
  if ! echo "$(date -Iseconds) report generated" >&3 2>/dev/null; then
    ok=0
  fi

  # 保持は直近5件だけ
  ls -1t "$REPORTS"/report-*.txt 2>/dev/null | tail -n +6 | xargs -r rm -f

  if [ "$ok" = 1 ]; then
    echo "$FLAG" > "$STATE/flag.txt"
  else
    echo "レポートを書き出せません: $LOGDIR に書き込めない状態です" >&2
    rm -f "$STATE/flag.txt"
  fi

  sleep 5 3>&-
done
