#!/bin/sh
# 復旧できたかを判定する。
#
#   ./verify.sh --status       今のサーバの状態を表示する
#   ./verify.sh 'FLAG{...}'    取得したFLAGを判定する
#
# 真実の情報源は「reportdが今まさに書き出せているか」。復旧していなければ
# 成果物は消えるので、過去に一度出たFLAGを貼っても通らない。
set -e

cd "$(dirname "$0")"

SSH_OPTS="-i ssh/id_ed25519 -p 2222 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=5"

remote() {
  ssh $SSH_OPTS ec2-user@localhost "$1" 2>/dev/null
}

if [ ! -f ssh/id_ed25519 ]; then
  echo "まだサーバが用意されていません。./new-case.sh を実行してください。"
  exit 1
fi

if [ "$1" = "--status" ]; then
  echo "サーバの状態:"
  remote 'systemctl is-active reportd' | sed 's/^/  reportd        : /'
  remote 'df -h /var/log/reportd | tail -1' | awk '{printf "  ディスク使用   : %s / %s (%s)\n", $3, $2, $5}'
  remote 'df -i /var/log/reportd | tail -1' | awk '{printf "  inode使用      : %s / %s (%s)\n", $3, $2, $5}'
  if remote 'test -f /var/lib/reportd/flag.txt && echo yes' | grep -q yes; then
    age=$(remote 'echo $(( $(date +%s) - $(stat -c %Y /var/lib/reportd/flag.txt) ))')
    echo "  成果物         : あり (${age}秒前に更新)"
  else
    echo "  成果物         : なし (まだ書き出せていない)"
  fi
  exit 0
fi

USER_FLAG="$1"

if [ -z "$USER_FLAG" ]; then
  echo "使い方: ./verify.sh 'FLAG{取得した値}'   (状態を見るなら ./verify.sh --status)"
  exit 1
fi

ACTUAL=$(remote 'cat /var/lib/reportd/flag.txt' | tr -d '\r\n' || true)

if [ -z "$ACTUAL" ]; then
  echo "NG: reportd がまだ成果物を書き出せていません。復旧が完了していません。"
  exit 1
fi

AGE=$(remote 'echo $(( $(date +%s) - $(stat -c %Y /var/lib/reportd/flag.txt) ))')
if [ "$AGE" -gt 20 ]; then
  echo "NG: 成果物が${AGE}秒前から更新されていません。一時的に書けただけで、また詰まっています。"
  exit 1
fi

if [ "$USER_FLAG" = "$ACTUAL" ]; then
  echo "正解! $USER_FLAG"
  echo "  reportd は復旧し、レポートを書き出し続けています。"
  exit 0
else
  echo "不正解: そのFLAGは今動いているサーバのものと一致しません。"
  exit 1
fi
