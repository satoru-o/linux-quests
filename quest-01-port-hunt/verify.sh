#!/bin/sh
# クリア確認用スクリプト。
# 自分で取得したFLAGを引数で渡すと、クエストのコンテナ内にある本物のflag.txtと
# 一致するか判定する。
#
# 使い方:
#   ./verify.sh 'FLAG{...}'
set -e

cd "$(dirname "$0")"

USER_FLAG="$1"

if [ -z "$USER_FLAG" ]; then
  echo "使い方: ./verify.sh 'FLAG{取得した値}'"
  exit 1
fi

ACTUAL_FLAG=$(docker compose exec -T port-hunt cat flag.txt 2>/dev/null) || {
  echo "NG: クエストのコンテナ(port-hunt)からflag.txtを読み出せません。docker compose psで状態を確認してください。"
  exit 1
}

if [ "$USER_FLAG" = "$ACTUAL_FLAG" ]; then
  echo "正解! $USER_FLAG"
  exit 0
else
  echo "不正解: そのFLAGはこのクエストのものと一致しません。"
  exit 1
fi
