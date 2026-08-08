#!/bin/sh
# 診断結果(原因)を申告する。当たっていればFLAGが手に入る。
#
#   ./answer.sh --list     申告できる原因の一覧
#   ./answer.sh <原因ID>   申告する
#   ./answer.sh --giveup   降参して答えを見る
set -e

cd "$(dirname "$0")"

CASES="process-down bind-localhost wrong-port network-split wrong-address blackhole app-error app-notfound"

describe() {
  case "$1" in
    process-down)   echo "プロセス/コンテナ自体が動いていない" ;;
    bind-localhost) echo "127.0.0.1でlistenしていて外から届かない" ;;
    wrong-port)     echo "想定と違うポートでlistenしている" ;;
    network-split)  echo "相手と別のネットワークにいて名前が引けない" ;;
    wrong-address)  echo "名前は引けるが、想定と違うアドレスを指している" ;;
    blackhole)      echo "TCPは繋がるが応答が返ってこない" ;;
    app-error)      echo "HTTPは通るがアプリがエラーを返す(5xx)" ;;
    app-notfound)   echo "HTTPは通るがそのパスが存在しない(4xx)" ;;
  esac
}

rung() {
  case "$1" in
    process-down)                 echo "第1段: プロセスは生きているか" ;;
    bind-localhost|wrong-port)    echo "第2段: 期待どおりlistenしているか" ;;
    network-split|wrong-address)  echo "第3段: 名前は引けるか / どこを指しているか" ;;
    blackhole)                    echo "第4段: TCPで繋がり、応答が返るか" ;;
    app-error|app-notfound)       echo "第5段: アプリが正しく返しているか" ;;
  esac
}

if [ "$1" = "--list" ]; then
  echo "申告できる原因:"
  for c in $CASES; do
    printf '  %-15s %s\n' "$c" "$(describe "$c")"
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
  echo "決めつけずに、下の層から順に確認し直すこと。どこまでは正常だったかを言えるようにする。"
  exit 1
fi

CID=$(docker compose ps -aq target 2>/dev/null | head -n 1)
FLAG=$(docker cp "$CID:/flag.txt" - 2>/dev/null | tar -xO 2>/dev/null | tr -d '\n' || true)

echo "正解! $GUESS ($(describe "$GUESS"))"
echo "  $(rung "$GUESS")"
if [ -n "$FLAG" ]; then
  echo "  $FLAG"
fi
echo
echo "次の症例に進むには ./new-case.sh"
