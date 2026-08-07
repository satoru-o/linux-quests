#!/bin/sh
# クリア確認用スクリプト。
# 自分で取得したFLAGを引数で渡すと判定する。
#
# 真実の情報源は「ホスト側からapiの/checkにHTTPアクセスした結果」。
# apiがdbに正しく到達できていない限りstatus=okにならないため、
# 名前解決の問題を解決しないとNGのまま。
#
# 使い方:
#   ./verify.sh 'FLAG{...}'
set -e

USER_FLAG="$1"

if [ -z "$USER_FLAG" ]; then
  echo "使い方: ./verify.sh 'FLAG{取得した値}'"
  exit 1
fi

URL="http://localhost:5000/check"

RESPONSE=$(curl -fsS "$URL" 2>/dev/null) || {
  echo "NG: $URL にアクセスできません。apiコンテナが起動しているか確認してください(docker compose up -d --build)。"
  exit 1
}

STATUS=$(echo "$RESPONSE" | grep -o '"status":"[^"]*"' | cut -d'"' -f4)

if [ "$STATUS" != "ok" ]; then
  echo "NG: /checkがまだ正常応答していません。"
  echo "  response: $RESPONSE"
  exit 1
fi

ACTUAL_FLAG=$(echo "$RESPONSE" | grep -o '"flag":"[^"]*"' | cut -d'"' -f4)

if [ "$USER_FLAG" = "$ACTUAL_FLAG" ]; then
  echo "正解! $USER_FLAG"
  exit 0
else
  echo "不正解: そのFLAGはこのクエストのものと一致しません。"
  exit 1
fi
