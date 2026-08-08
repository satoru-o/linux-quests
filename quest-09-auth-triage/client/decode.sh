#!/bin/sh
# 手元のトークンの中身を表示する。署名の検証はしない。
# 「何を主張しているトークンか」と「今が何時か」を突き合わせるためのもの。
T=$(cat /creds/token 2>/dev/null)
if [ -z "$T" ]; then
  echo "トークンがありません"
  exit 1
fi

seg() {
  P=$(echo "$T" | cut -d. -f"$1" | tr '_-' '/+')
  case $(( ${#P} % 4 )) in
    2) P="$P==" ;;
    3) P="$P=" ;;
  esac
  echo "$P" | base64 -d 2>/dev/null | (jq . 2>/dev/null || cat)
  echo
}

echo "--- header (第1セグメント) ---"
seg 1
echo "--- payload (第2セグメント) ---"
seg 2
echo "--- 現在時刻 ---"
echo "  epoch: $(date +%s)"
echo "  utc  : $(date -u)"
echo
echo "--- トークンの形 ---"
echo "  セグメント数: $(echo "$T" | tr '.' '\n' | wc -l)  (正常なJWTは3)"
echo "  全体の長さ  : ${#T}"
