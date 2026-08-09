#!/bin/sh
# 復旧できたかを判定する。
#
#   ./verify.sh --status       今のサーバの状態を表示する
#   ./verify.sh 'FLAG{...}'    取得したFLAGを判定する
set -e

cd "$(dirname "$0")"

SSH_OPTS="-i ssh/id_ed25519 -p 2226 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=5"

remote() {
  ssh $SSH_OPTS ec2-user@localhost "$1" 2>/dev/null
}

if [ ! -f ssh/id_ed25519 ]; then
  echo "まだサーバが用意されていません。./new-case.sh を実行してください。"
  exit 1
fi

if [ "$1" = "--status" ]; then
  echo "サーバの状態:"
  remote 'systemctl is-active nginx' | sed 's/^/  nginx          : /'
  echo -n "  検証つき接続   : "
  remote 'curl -sS -o /dev/null -m 8 -w "%{http_code}\n" https://reports.internal/api/report 2>&1 | tail -1'
  echo -n "  検証なし接続   : "
  remote 'c=$(curl -ksS -o /dev/null -m 8 -w "%{http_code}" https://reports.internal/api/report 2>/dev/null); echo "${c:-000}"'
  if remote 'test -f /var/lib/tls-watchdog/flag.txt && echo yes' | grep -q yes; then
    age=$(remote 'echo $(( $(date +%s) - $(stat -c %Y /var/lib/tls-watchdog/flag.txt) ))')
    echo "  成果物         : あり (${age}秒前に更新)"
  else
    echo "  成果物         : なし (検証つきの接続が通っていない)"
  fi
  exit 0
fi

USER_FLAG="$1"

if [ -z "$USER_FLAG" ]; then
  echo "使い方: ./verify.sh 'FLAG{取得した値}'   (状態を見るなら ./verify.sh --status)"
  exit 1
fi

ACTUAL=$(remote 'cat /var/lib/tls-watchdog/flag.txt' | tr -d '\r\n' || true)

if [ -z "$ACTUAL" ]; then
  echo "NG: まだ成果物がありません。検証つきの接続が通っていません。"
  exit 1
fi

AGE=$(remote 'echo $(( $(date +%s) - $(stat -c %Y /var/lib/tls-watchdog/flag.txt) ))')
if [ "$AGE" -gt 40 ]; then
  echo "NG: 成果物が${AGE}秒前から更新されていません。また失敗し始めています。"
  exit 1
fi

if [ "$USER_FLAG" = "$ACTUAL" ]; then
  echo "正解! $USER_FLAG"
  echo "  検証つきの接続が通るようになりました。"
  exit 0
else
  echo "不正解: そのFLAGは今動いているサーバのものと一致しません。"
  exit 1
fi
