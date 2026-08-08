#!/bin/bash
# 注文APIの本体(ダミー)。設定を読んで、動いている間だけ成果物を置く。
# FLAGはこのプロセスのメモリ上にしか存在しない。
set -e

CONF=/etc/orderapi/app.conf
if [ ! -f "$CONF" ]; then
  echo "設定ファイルがありません: $CONF" >&2
  exit 1
fi
# shellcheck disable=SC1090
. "$CONF"
: "${LISTEN_PORT:?LISTEN_PORT が設定されていません}"

FLAG="FLAG{$(head -c 16 /dev/urandom | md5sum | cut -d' ' -f1)}"
STATE=/var/lib/orderapi

echo "orderapi を起動しました (port=$LISTEN_PORT, cwd=$(pwd))"

while true; do
  echo "$FLAG" > "$STATE/flag.txt"
  sleep 5
done
