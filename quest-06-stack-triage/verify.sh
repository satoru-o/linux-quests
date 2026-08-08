#!/bin/sh
# クリア確認用スクリプト。
# 自分で取得したFLAGを引数で渡すと、3つのうちどれに当たるかを判定する。
#
# 真実の情報源はそれぞれ別の場所に置いてある。どれも「その段階を実際に
# 解決していないと値が存在しない」経路なので、途中を飛ばして正解を
# 取り出すことはできない。
#
# 使い方:
#   ./verify.sh 'FLAG{...}'    取得したFLAGを判定する
#   ./verify.sh --status       今どこまで進んでいるかだけ表示する
set -e

cd "$(dirname "$0")"

URL_ROOT="http://localhost:8080/"
URL_REPORT="http://localhost:8080/report"

get_stage1() {
  curl -fsS --max-time 5 "$URL_ROOT" 2>/dev/null | grep -o 'FLAG{[0-9a-f]*}' | head -n 1
}

get_stage2() {
  docker compose logs client 2>/dev/null | grep -o 'FLAG{[0-9a-f]*}' | head -n 1
}

get_stage3() {
  curl -fsS --max-time 5 "$URL_REPORT" 2>/dev/null |
    grep -o '"flag":"FLAG{[0-9a-f]*}"' | cut -d'"' -f4 | head -n 1
}

STAGE1=$(get_stage1 || true)
STAGE2=$(get_stage2 || true)
STAGE3=$(get_stage3 || true)

print_status() {
  echo "進捗:"
  [ -n "$STAGE1" ] && echo "  [1] serverへの疎通         : 到達可能" || echo "  [1] serverへの疎通         : まだ"
  [ -n "$STAGE2" ] && echo "  [2] client -> server の連携: 成立" || echo "  [2] client -> server の連携: まだ"
  [ -n "$STAGE3" ] && echo "  [3] レポートの受け渡し     : 成立" || echo "  [3] レポートの受け渡し     : まだ"
}

if [ "$1" = "--status" ]; then
  print_status
  exit 0
fi

USER_FLAG="$1"

if [ -z "$USER_FLAG" ]; then
  echo "使い方: ./verify.sh 'FLAG{取得した値}'   (進捗だけ見るなら ./verify.sh --status)"
  exit 1
fi

if [ -n "$STAGE1" ] && [ "$USER_FLAG" = "$STAGE1" ]; then
  echo "正解! [1/3] serverへの疎通  $USER_FLAG"
  exit 0
fi

if [ -n "$STAGE2" ] && [ "$USER_FLAG" = "$STAGE2" ]; then
  echo "正解! [2/3] client -> server の連携  $USER_FLAG"
  exit 0
fi

if [ -n "$STAGE3" ] && [ "$USER_FLAG" = "$STAGE3" ]; then
  echo "正解! [3/3] レポートの受け渡し  $USER_FLAG"
  exit 0
fi

echo "不正解: そのFLAGは、現時点で到達できているどの段階のものとも一致しません。"
print_status
exit 1
