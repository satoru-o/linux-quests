#!/bin/sh
# 診断結果(原因)を申告する。当たっていればFLAGが手に入る。
#
#   ./answer.sh --list     申告できる原因の一覧
#   ./answer.sh <原因ID>   申告する
#   ./answer.sh --giveup   降参して答えを見る
set -e

cd "$(dirname "$0")"

BASIC="no-credential wrong-scheme token-expired wrong-audience bad-signature revoked-token insufficient-scope proxy-strips-header"
HARD="clock-skew wrong-algorithm double-bearer token-truncated proxy-overwrites-auth rate-limited"
CASES="$BASIC $HARD"

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
    clock-skew)          echo "時計のズレで、まだ有効になっていないトークン" ;;
    wrong-algorithm)     echo "署名アルゴリズムが受け側の想定と違う" ;;
    double-bearer)       echo "スキームが二重になっている(Bearer Bearer ...)" ;;
    token-truncated)     echo "トークンが途中で欠けている" ;;
    proxy-overwrites-auth) echo "途中の経路が別の資格情報で上書きしている" ;;
    rate-limited)        echo "認証は通っているが回数制限に当たっている(429)" ;;
  esac
}

rung() {
  case "$1" in
    insufficient-scope)                    echo "第2段: ステータスコード(403は認可の失敗。認証は成功している)" ;;
    no-credential)                         echo "第3段: クライアントが実際に何を送ったか" ;;
    proxy-strips-header)                   echo "第3段と第4段の差分: 送ったのに届いていない" ;;
    wrong-scheme|bad-signature|revoked-token) echo "第4段: サーバに何が届き、どこで弾かれたか" ;;
    token-expired|wrong-audience|clock-skew) echo "第5段: トークンの中身(claims)を期待値と突き合わせる" ;;
    wrong-algorithm)                       echo "第5段: ペイロードではなくヘッダ(第1セグメント)を見る" ;;
    double-bearer|token-truncated)         echo "第3段: 送った文字列そのものを見る" ;;
    proxy-overwrites-auth)                 echo "第3段と第4段の差分: 送ったものと届いたものが別人格" ;;
    rate-limited)                          echo "第2段: ステータスコード(429は認証でも認可でもない)" ;;
  esac
}

if [ "$1" = "--list" ]; then
  echo "申告できる原因:"
  echo "  [初級]"
  for c in $BASIC; do
    printf '    %-22s %s\n' "$c" "$(describe "$c")"
  done
  echo "  [上級] (./new-case.sh --hard で出題)"
  for c in $HARD; do
    printf '    %-22s %s\n' "$c" "$(describe "$c")"
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
