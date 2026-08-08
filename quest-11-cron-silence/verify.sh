#!/bin/sh
# 復旧できたかを判定する。
#
#   ./verify.sh --status       今のサーバの状態を表示する
#   ./verify.sh 'FLAG{...}'    取得したFLAGを判定する
#
# 真実の情報源は「集計結果が今も更新され続けているか」。cronが回っていなければ
# 成果物は消えるので、過去に一度出たFLAGを貼っても通らない。
set -e

cd "$(dirname "$0")"

SSH_OPTS="-i ssh/id_ed25519 -p 2223 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=5"

remote() {
  ssh $SSH_OPTS ec2-user@localhost "$1" 2>/dev/null
}

if [ ! -f ssh/id_ed25519 ]; then
  echo "まだサーバが用意されていません。./new-case.sh を実行してください。"
  exit 1
fi

if [ "$1" = "--status" ]; then
  echo "サーバの状態:"
  remote 'systemctl is-active cron' | sed 's/^/  cron           : /'
  if remote 'test -f /var/lib/batch/result.json && echo yes' | grep -q yes; then
    age=$(remote 'echo $(( $(date +%s) - $(stat -c %Y /var/lib/batch/result.json) ))')
    echo "  集計結果       : あり (${age}秒前に更新)"
  else
    echo "  集計結果       : なし (一度も作られていない)"
  fi
  if remote 'test -f /var/lib/batch/flag.txt && echo yes' | grep -q yes; then
    echo "  成果物         : あり"
  else
    echo "  成果物         : なし (定期実行が復旧していない)"
  fi
  exit 0
fi

USER_FLAG="$1"

if [ -z "$USER_FLAG" ]; then
  echo "使い方: ./verify.sh 'FLAG{取得した値}'   (状態を見るなら ./verify.sh --status)"
  exit 1
fi

if ! remote 'systemctl is-active cron' | grep -q '^active'; then
  echo "NG: cron が動いていません。定期実行が復旧していません。"
  exit 1
fi

ACTUAL=$(remote 'cat /var/lib/batch/flag.txt' | tr -d '\r\n' || true)

if [ -z "$ACTUAL" ]; then
  echo "NG: まだ成果物がありません。集計が定期的に走る状態になっていません。"
  exit 1
fi

AGE=$(remote 'echo $(( $(date +%s) - $(stat -c %Y /var/lib/batch/result.json) ))')
if [ "$AGE" -gt 90 ]; then
  echo "NG: 集計結果が${AGE}秒前から更新されていません。定期実行が続いていません。"
  exit 1
fi

if [ "$USER_FLAG" = "$ACTUAL" ]; then
  echo "正解! $USER_FLAG"
  echo "  集計が定期的に走る状態に戻りました。"
  exit 0
else
  echo "不正解: そのFLAGは今動いているサーバのものと一致しません。"
  exit 1
fi
