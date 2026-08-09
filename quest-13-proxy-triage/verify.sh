#!/bin/sh
# 復旧できたかを判定する。
#
#   ./verify.sh --status       今のサーバの状態を表示する
#   ./verify.sh 'FLAG{...}'    取得したFLAGを判定する
set -e

cd "$(dirname "$0")"

SSH_OPTS="-i ssh/id_ed25519 -p 2225 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=5"

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
  up=$(remote 'systemctl is-active backend@9001 backend@9002 backend@9003 | grep -c "^active"')
  echo "  バックエンド   : ${up}/3 稼働"
  echo -n "  経路の応答     : "
  remote 'for i in 1 2 3 4 5 6; do c=$(curl -sS -o /dev/null -m 6 -w "%{http_code}" http://127.0.0.1/api/report 2>/dev/null); printf "%s " "${c:-000}"; done; echo'
  echo -n "  /api/slow      : "
  remote 'c=$(curl -sS -o /dev/null -m 15 -w "%{http_code}" http://127.0.0.1/api/slow 2>/dev/null); echo "${c:-000}"'
  if remote 'test -f /var/lib/proxy-watchdog/flag.txt && echo yes' | grep -q yes; then
    age=$(remote 'echo $(( $(date +%s) - $(stat -c %Y /var/lib/proxy-watchdog/flag.txt) ))')
    echo "  成果物         : あり (${age}秒前に更新)"
  else
    echo "  成果物         : なし (経路が安定していない)"
  fi
  exit 0
fi

USER_FLAG="$1"

if [ -z "$USER_FLAG" ]; then
  echo "使い方: ./verify.sh 'FLAG{取得した値}'   (状態を見るなら ./verify.sh --status)"
  exit 1
fi

ACTUAL=$(remote 'cat /var/lib/proxy-watchdog/flag.txt' | tr -d '\r\n' || true)

if [ -z "$ACTUAL" ]; then
  echo "NG: まだ成果物がありません。経路が安定して通っていません。"
  exit 1
fi

AGE=$(remote 'echo $(( $(date +%s) - $(stat -c %Y /var/lib/proxy-watchdog/flag.txt) ))')
if [ "$AGE" -gt 40 ]; then
  echo "NG: 成果物が${AGE}秒前から更新されていません。また失敗し始めています。"
  exit 1
fi

if [ "$USER_FLAG" = "$ACTUAL" ]; then
  echo "正解! $USER_FLAG"
  echo "  利用者と同じ経路が安定して通るようになりました。"
  exit 0
else
  echo "不正解: そのFLAGは今動いているサーバのものと一致しません。"
  exit 1
fi
