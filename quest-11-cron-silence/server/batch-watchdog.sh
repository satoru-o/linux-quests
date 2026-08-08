#!/bin/bash
# 集計結果が定期的に更新されているかを見張る。
# 更新され続けている間だけ成果物(flag.txt)を置く。
# FLAGはこのプロセスのメモリ上にしか存在しない。
RESULT=/var/lib/batch/result.json
STATE=/var/lib/batch

FLAG="FLAG{$(head -c 16 /dev/urandom | md5sum | cut -d' ' -f1)}"
mkdir -p "$STATE"
rm -f "$STATE/flag.txt"

while true; do
  if [ -f "$RESULT" ] && [ $(( $(date +%s) - $(stat -c %Y "$RESULT") )) -le 90 ]; then
    echo "$FLAG" > "$STATE/flag.txt"
  else
    rm -f "$STATE/flag.txt"
  fi
  sleep 10
done
