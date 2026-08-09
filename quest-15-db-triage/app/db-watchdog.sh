#!/bin/bash
# 利用者と同じ経路でレポートAPIの3つの機能を叩き続ける。
# 3つとも期待どおりに動いている間だけ成果物(flag.txt)を置く。
# FLAGはこのプロセスのメモリ上にしか存在しない。
STATE=/var/lib/db-watchdog
BASE=http://127.0.0.1:8080
FLAG="FLAG{$(head -c 16 /dev/urandom | md5sum | cut -d' ' -f1)}"
mkdir -p "$STATE"
rm -f "$STATE/flag.txt"

hit() {
  # $1=method $2=path -> "HTTPコード<TAB>本文"
  curl -sS -m 25 -X "$1" -o /tmp/wd.body -w '%{http_code}' "$BASE$2" 2>/tmp/wd.err
  printf '\t'
  cat /tmp/wd.body 2>/dev/null
}

while true; do
  ok=1
  why=""

  out=$(hit GET /api/reports)
  code=${out%%$'\t'*}
  body=${out#*$'\t'}
  if [ "$code" != 200 ]; then
    ok=0; why="一覧の取得に失敗 ($code) $body"
  elif [ "$(echo "$body" | jq -r '.count // 0')" -lt 1 ]; then
    ok=0; why="一覧は返るが0件 $body"
  fi

  if [ "$ok" = 1 ]; then
    out=$(hit POST /api/reports)
    code=${out%%$'\t'*}
    body=${out#*$'\t'}
    if [ "$code" != 201 ]; then
      ok=0; why="登録に失敗 ($code) $body"
    fi
  fi

  if [ "$ok" = 1 ]; then
    out=$(hit GET /api/summary)
    code=${out%%$'\t'*}
    body=${out#*$'\t'}
    if [ "$code" != 200 ]; then
      ok=0; why="集計に失敗 ($code) $body"
    elif [ "$(echo "$body" | jq -r '.count // 0')" -lt 1 ]; then
      ok=0; why="集計は返るが0件 $body"
    fi
  fi

  if [ "$ok" = 1 ]; then
    echo "$FLAG" > "$STATE/flag.txt"
  else
    echo "$(date -Iseconds) $why" >&2
    rm -f "$STATE/flag.txt"
  fi

  sleep 10
done
