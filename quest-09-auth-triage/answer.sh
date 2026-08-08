#!/bin/sh
# 診断結果(原因)を申告する。当たっていればFLAGが手に入る。
#
#   ./answer.sh --list     申告できる原因の一覧
#   ./answer.sh <原因ID>   申告する
#   ./answer.sh --giveup   降参して答えを見る
set -e

cd "$(dirname "$0")"

CASES="no-credential wrong-scheme token-expired wrong-audience bad-signature revoked-token insufficient-scope proxy-strips-header"

describe() {
  case "$1" in
    no-credential)       echo "クライアントが認証情報を送っていない" ;;
    wrong-scheme)        echo "スキームがBearerではない" ;;
    token-expired)       echo "トークンの有効期限が切れている" ;;
    wrong-audience)      echo "別のサービス宛(aud違い)のトークンを使っている" ;;
    bad-signature)       echo "署名が合わない(鍵違いか改ざん)" ;;
    revoked-token)       echo "形式は正しいが失効済みのトークン" ;;
    insufficient-scope)  echo "認証は通っているがスコープが足りない(403)" ;;
    proxy-strips-header) echo "クライアントは送っているが、途中の経路で消えている" ;;
  esac
}

rung() {
  case "$1" in
    insufficient-scope)                    echo "第2段: ステータスコード(403は認可の失敗。認証は成功している)" ;;
    no-credential)                         echo "第3段: クライアントが実際に何を送ったか" ;;
    proxy-strips-header)                   echo "第3段と第4段の差分: 送ったのに届いていない" ;;
    wrong-scheme|bad-signature|revoked-token) echo "第4段: サーバに何が届き、どこで弾かれたか" ;;
    token-expired|wrong-audience)          echo "第5段: トークンの中身(claims)を期待値と突き合わせる" ;;
  esac
}

if [ "$1" = "--list" ]; then
  echo "申告できる原因:"
  for c in $CASES; do
    printf '  %-20s %s\n' "$c" "$(describe "$c")"
  done
  exit 0
fi

if [ ! -f .state ]; then
  echo "症例がまだ用意されていません。まず ./new-case.sh を実行してください。"
  exit 1
fi

. ./.state

if [ "$1" = "--giveup" ]; then
  for c in $CASES; do
    if [ "$(printf '%s' "$c" | sha256sum | cut -d' ' -f1)" = "$CASE_HASH" ]; then
      echo "今回の原因: $c ($(describe "$c"))"
      echo "  $(rung "$c")"
      echo
      echo "次の症例に進むには ./new-case.sh"
      exit 0
    fi
  done
  echo "症例を特定できませんでした。./new-case.sh でやり直してください。"
  exit 1
fi

GUESS="$1"

if [ -z "$GUESS" ]; then
  echo "使い方: ./answer.sh <原因ID>   (一覧は ./answer.sh --list)"
  exit 1
fi

if ! echo " $CASES " | grep -q " $GUESS "; then
  echo "そのIDは一覧にありません: $GUESS"
  echo "一覧は ./answer.sh --list"
  exit 1
fi

if [ "$(printf '%s' "$GUESS" | sha256sum | cut -d' ' -f1)" != "$CASE_HASH" ]; then
  echo "不正解: $GUESS ではない。"
  echo "レスポンスだけで決めつけず、送ったもの・届いたもの・トークンの中身を順に確認し直すこと。"
  exit 1
fi

CID=$(docker compose ps -aq fixture 2>/dev/null | head -n 1)
FLAG=$(docker cp "$CID:/flag.txt" - 2>/dev/null | tar -xO 2>/dev/null | tr -d '\n' || true)

echo "正解! $GUESS ($(describe "$GUESS"))"
echo "  $(rung "$GUESS")"
if [ -n "$FLAG" ]; then
  echo "  $FLAG"
fi
echo
echo "次の症例に進むには ./new-case.sh"
