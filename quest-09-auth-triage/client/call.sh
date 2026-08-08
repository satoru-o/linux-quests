#!/bin/sh
# APIを1回呼ぶ。レスポンスをヘッダ込みで表示する。
TOKEN=$(cat /creds/token 2>/dev/null)
SCHEME="${AUTH_SCHEME:-Bearer}"
TARGET="${TARGET:-http://proxy:8080/reports}"

if [ "${SEND_AUTH:-1}" = "1" ]; then
  echo "# 送信するヘッダ: Authorization: $SCHEME <token>"
  curl -sS -i -m 5 -H "Authorization: $SCHEME $TOKEN" "$TARGET"
else
  echo "# Authorizationヘッダは送っていない"
  curl -sS -i -m 5 "$TARGET"
fi
echo
