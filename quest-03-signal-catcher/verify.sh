#!/bin/sh
# クリア確認用スクリプト。
# 自分で取得したFLAGを引数で渡すと判定する。
#
# 真実の情報源は「signal-catcherコンテナの/flag.txtの中身」。
# 停止後のコンテナでもdocker cpなら中身を取り出せるため、docker execではなく
# docker cpを使う。
#
# 使い方:
#   ./verify.sh 'FLAG{...}'
set -e

USER_FLAG="$1"

if [ -z "$USER_FLAG" ]; then
  echo "使い方: ./verify.sh 'FLAG{取得した値}'"
  exit 1
fi

ACTUAL_FLAG=$(docker cp signal-catcher:/flag.txt - 2>/dev/null | tar -xO 2>/dev/null) || true

if [ -z "$ACTUAL_FLAG" ]; then
  echo "NG: signal-catcherコンテナから/flag.txtを取り出せません。正しい終わらせ方ができているか確認してください。"
  exit 1
fi

if [ "$USER_FLAG" = "$ACTUAL_FLAG" ]; then
  echo "正解! $USER_FLAG"
  exit 0
else
  echo "不正解: そのFLAGはこのクエストのものと一致しません。"
  exit 1
fi
