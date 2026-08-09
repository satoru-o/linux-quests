#!/bin/bash
# 前段のnginx越しに、利用者と同じ経路で叩き続ける見張り役。
# すべて正常に返っている間だけ成果物(flag.txt)を置く。
# FLAGはこのプロセスのメモリ上にしか存在しない。
STATE=/var/lib/proxy-watchdog
FLAG="FLAG{$(head -c 16 /dev/urandom | md5sum | cut -d' ' -f1)}"
mkdir -p "$STATE"
rm -f "$STATE/flag.txt"

check() {
  # 3台に均等に振られるよう、まとめて叩いて全部200であることを求める
  for _ in $(seq 1 12); do
    code=$(curl -sS -o /dev/null -m 5 -w '%{http_code}' http://127.0.0.1/api/report 2>/dev/null || echo 000)
    [ "$code" = "200" ] || { echo "  /api/report が $code を返しました" >&2; return 1; }
  done
  # 時間のかかる処理も最後まで通ること
  code=$(curl -sS -o /dev/null -m 15 -w '%{http_code}' http://127.0.0.1/api/slow 2>/dev/null || echo 000)
  [ "$code" = "200" ] || { echo "  /api/slow が $code を返しました" >&2; return 1; }
  return 0
}

while true; do
  if check; then
    echo "$FLAG" > "$STATE/flag.txt"
  else
    echo "$(date -Iseconds) 経路が正常ではありません" >&2
    rm -f "$STATE/flag.txt"
  fi
  sleep 10
done
