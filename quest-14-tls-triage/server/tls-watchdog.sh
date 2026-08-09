#!/bin/bash
# 利用者と同じやり方で https://reports.internal を検証つきで叩き続ける。
# 通っている間だけ成果物(flag.txt)を置く。
# FLAGはこのプロセスのメモリ上にしか存在しない。
STATE=/var/lib/tls-watchdog
FLAG="FLAG{$(head -c 16 /dev/urandom | md5sum | cut -d' ' -f1)}"
mkdir -p "$STATE"
rm -f "$STATE/flag.txt"

while true; do
  out=$(curl -sS -o /dev/null -m 8 -w '%{http_code}' https://reports.internal/api/report 2>&1)
  rc=$?
  if [ "$rc" = 0 ] && [ "$out" = "200" ]; then
    echo "$FLAG" > "$STATE/flag.txt"
  else
    echo "$(date -Iseconds) 検証つきの接続に失敗しました: $out" >&2
    rm -f "$STATE/flag.txt"
  fi
  sleep 10
done
