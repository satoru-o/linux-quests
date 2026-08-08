#!/bin/sh
# 手元のトークンのペイロード(claims)をデコードして表示する。
# 署名の検証はしない。あくまで「何を主張しているトークンか」を見るためのもの。
T=$(cat /creds/token 2>/dev/null)
if [ -z "$T" ]; then
  echo "トークンがありません"
  exit 1
fi

P=$(echo "$T" | cut -d. -f2 | tr '_-' '/+')
case $(( ${#P} % 4 )) in
  2) P="$P==" ;;
  3) P="$P=" ;;
esac

echo "$P" | base64 -d 2>/dev/null | (jq . 2>/dev/null || cat)
echo
