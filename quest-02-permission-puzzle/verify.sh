#!/bin/sh
# クリア確認用スクリプト。
# 自分で取得したFLAGを引数で渡すと判定する。
#
# 真実の情報源は「appuserとしてコンテナに入り/secret/flag.txtを読めるか」に置く。
# rootで覗いて読む方法(docker compose exec -u root ...)は今回の本題(パーミッションの
# 解決)を回避してしまうため使わない。
#
# 使い方:
#   ./verify.sh 'FLAG{...}'
set -e

USER_FLAG="$1"

if [ -z "$USER_FLAG" ]; then
  echo "使い方: ./verify.sh 'FLAG{取得した値}'"
  exit 1
fi

ACTUAL_FLAG=$(docker compose exec -T permission-puzzle cat /secret/flag.txt 2>/dev/null) || {
  echo "NG: permission-puzzleコンテナの/secret/flag.txtを(appuserとして)読めません。パーミッションの問題を解決できているか確認してください。"
  exit 1
}

if [ "$USER_FLAG" = "$ACTUAL_FLAG" ]; then
  echo "正解! $USER_FLAG"
  exit 0
else
  echo "不正解: そのFLAGはこのクエストのものと一致しません。"
  exit 1
fi
