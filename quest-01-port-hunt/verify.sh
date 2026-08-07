#!/bin/sh
# クリア確認用スクリプト。
# 自分で取得したFLAGを引数で渡すと判定する。
#
# 真実の情報源は「ホスト側からポート8080経由でHTTPアクセスできるか」に置く。
# docker execでコンテナに直接入って中のファイルを読む方法だと、ポート公開が
# 失敗していても(=このクエストの本題を解決していなくても)コンテナ自体さえ
# 起動していれば通ってしまい、検証として自家撞着になるため使わない。
#
# 使い方:
#   ./verify.sh 'FLAG{...}'
set -e

USER_FLAG="$1"

if [ -z "$USER_FLAG" ]; then
  echo "使い方: ./verify.sh 'FLAG{取得した値}'"
  exit 1
fi

URL="http://localhost:8080/flag.txt"

ACTUAL_FLAG=$(curl -fsS "$URL" 2>/dev/null) || {
  echo "NG: $URL にアクセスできません。ポート8080の競合を解決してコンテナを起動できているか確認してください。"
  exit 1
}

if [ "$USER_FLAG" = "$ACTUAL_FLAG" ]; then
  echo "正解! $USER_FLAG"
  exit 0
else
  echo "不正解: そのFLAGはこのクエストのものと一致しません。"
  exit 1
fi
