#!/bin/sh
# クリア確認用スクリプト。
# 自分で取得したFLAGを引数で渡すと判定する。
#
# 真実の情報源は「log-divingコンテナ内のaccess.log自体」。
#
# 使い方:
#   ./verify.sh 'FLAG{...}'
set -e

USER_FLAG="$1"

if [ -z "$USER_FLAG" ]; then
  echo "使い方: ./verify.sh 'FLAG{取得した値}'"
  exit 1
fi

ACTUAL_FLAG=$(docker compose exec -T log-diving grep -o 'FLAG{[0-9a-f]*}' /var/log/app/access.log 2>/dev/null) || true

if [ -z "$ACTUAL_FLAG" ]; then
  echo "NG: log-divingコンテナのaccess.logからFLAGを取り出せません。コンテナが起動しているか確認してください(docker compose up -d --build)。"
  exit 1
fi

if [ "$USER_FLAG" = "$ACTUAL_FLAG" ]; then
  echo "正解! $USER_FLAG"
  exit 0
else
  echo "不正解: そのFLAGはこのクエストのものと一致しません。"
  exit 1
fi
