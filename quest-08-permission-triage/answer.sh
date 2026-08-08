#!/bin/sh
# 診断結果(原因)を申告する。当たっていればFLAGが手に入る。
#
#   ./answer.sh --list     申告できる原因の一覧
#   ./answer.sh <原因ID>   申告する
#   ./answer.sh --giveup   降参して答えを見る
set -e

cd "$(dirname "$0")"

CASES="not-owner group-not-member no-read-bit dir-no-exec dir-no-read dir-no-write sticky-other readonly-mount"

describe() {
  case "$1" in
    not-owner)        echo "対象が他人の所有で、自分に許可が無い" ;;
    group-not-member) echo "グループには許可があるが、自分がそのグループに所属していない" ;;
    no-read-bit)      echo "自分が所有者だが、読み取りビットが落ちている" ;;
    dir-no-exec)      echo "親ディレクトリにx(実行)が無く、パスを辿れない" ;;
    dir-no-read)      echo "親ディレクトリにr(読み取り)が無く、一覧が取れない" ;;
    dir-no-write)     echo "親ディレクトリにw(書き込み)が無く、作成・削除ができない" ;;
    sticky-other)     echo "stickyビットのあるディレクトリで、他人のファイルを消せない" ;;
    readonly-mount)   echo "権限ビットではなく、マウントが読み取り専用" ;;
  esac
}

rung() {
  case "$1" in
    not-owner|no-read-bit)                    echo "第2段: 対象の所有者とモード" ;;
    group-not-member)                         echo "第1段と第2段の突き合わせ: 自分の所属と対象のグループ" ;;
    dir-no-exec|dir-no-read|dir-no-write)     echo "第3段: そこへ至る経路(親ディレクトリ)のビット" ;;
    sticky-other)                             echo "第3段: 親ディレクトリの特殊ビット" ;;
    readonly-mount)                           echo "第5段: 権限ビットの外側(マウントオプション)" ;;
  esac
}

if [ "$1" = "--list" ]; then
  echo "申告できる原因:"
  for c in $CASES; do
    printf '  %-18s %s\n' "$c" "$(describe "$c")"
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
  echo "エラーメッセージだけで決めつけず、id / ls -l / namei を順に確認し直すこと。"
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
