#!/bin/sh
# 復旧できたかを判定する。
#
#   ./verify.sh --status       今のサーバの状態を表示する
#   ./verify.sh 'FLAG{...}'    取得したFLAGを判定する
#
# 真実の情報源は「orderapi が今まさに動いているか」。止まれば成果物は
# 消えるので、過去に一度出たFLAGを貼っても通らない。
set -e

cd "$(dirname "$0")"

SSH_OPTS="-i ssh/id_ed25519 -p 2224 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=5"

remote() {
  ssh $SSH_OPTS ec2-user@localhost "$1" 2>/dev/null
}

if [ ! -f ssh/id_ed25519 ]; then
  echo "まだサーバが用意されていません。./new-case.sh を実行してください。"
  exit 1
fi

if [ "$1" = "--status" ]; then
  echo "サーバの状態:"
  remote 'systemctl is-active orderapi' | sed 's/^/  orderapi       : /'
  remote 'systemctl is-enabled orderapi' | sed 's/^/  自動起動       : /'
  if remote 'test -f /var/lib/orderapi/flag.txt && echo yes' | grep -q yes; then
    age=$(remote 'echo $(( $(date +%s) - $(stat -c %Y /var/lib/orderapi/flag.txt) ))')
    echo "  成果物         : あり (${age}秒前に更新)"
  else
    echo "  成果物         : なし (サービスが動いていない)"
  fi
  exit 0
fi

USER_FLAG="$1"

if [ -z "$USER_FLAG" ]; then
  echo "使い方: ./verify.sh 'FLAG{取得した値}'   (状態を見るなら ./verify.sh --status)"
  exit 1
fi

if ! remote 'systemctl is-active orderapi' | grep -q '^active'; then
  echo "NG: orderapi が動いていません。復旧が完了していません。"
  exit 1
fi

ACTUAL=$(remote 'cat /var/lib/orderapi/flag.txt' | tr -d '\r\n' || true)

if [ -z "$ACTUAL" ]; then
  echo "NG: まだ成果物がありません。サービスが正常に動き出していません。"
  exit 1
fi

AGE=$(remote 'echo $(( $(date +%s) - $(stat -c %Y /var/lib/orderapi/flag.txt) ))')
if [ "$AGE" -gt 20 ]; then
  echo "NG: 成果物が${AGE}秒前から更新されていません。サービスが動き続けていません。"
  exit 1
fi

if [ "$USER_FLAG" = "$ACTUAL" ]; then
  echo "正解! $USER_FLAG"
  echo "  orderapi は復旧し、動き続けています。"
  exit 0
else
  echo "不正解: そのFLAGは今動いているサーバのものと一致しません。"
  exit 1
fi
