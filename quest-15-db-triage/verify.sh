#!/bin/sh
# 復旧できたかを判定する。
#
#   ./verify.sh --status       今のサーバの状態を表示する
#   ./verify.sh 'FLAG{...}'    取得したFLAGを判定する
set -e

cd "$(dirname "$0")"

SSH_OPTS="-i ssh/id_ed25519 -p 2227 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=5"

remote() {
  ssh $SSH_OPTS ec2-user@localhost "$1" 2>/dev/null
}

probe() {
  # $1=method $2=path $3=期待するコード
  remote "curl -sS -m 25 -X $1 -o /tmp/v.body -w '%{http_code}' http://127.0.0.1:8080$2 2>/dev/null; echo; head -c 120 /tmp/v.body"
}

if [ ! -f ssh/id_ed25519 ]; then
  echo "まだサーバが用意されていません。./new-case.sh を実行してください。"
  exit 1
fi

if [ "$1" = "--status" ]; then
  echo "サーバの状態:"
  remote 'systemctl is-active reportapi' | sed 's/^/  reportapi  : /'
  remote 'pg_isready -h reportdb.internal -p 5432 -t 5 > /dev/null 2>&1 && echo reachable || echo unreachable' \
    | sed 's/^/  DBへの経路 : /'
  for spec in "GET /api/reports 一覧" "POST /api/reports 登録" "GET /api/summary 集計"; do
    m=$(echo "$spec" | cut -d' ' -f1)
    p=$(echo "$spec" | cut -d' ' -f2)
    label=$(echo "$spec" | cut -d' ' -f3)
    out=$(probe "$m" "$p")
    code=$(echo "$out" | head -1)
    body=$(echo "$out" | tail -n +2)
    printf '  %-10s : %s %s\n' "$label" "${code:-000}" "$body"
  done
  if remote 'test -f /var/lib/db-watchdog/flag.txt && echo yes' | grep -q yes; then
    age=$(remote 'echo $(( $(date +%s) - $(stat -c %Y /var/lib/db-watchdog/flag.txt) ))')
    echo "  成果物     : あり (${age}秒前に更新)"
  else
    echo "  成果物     : なし (3つ揃って通っていない)"
  fi
  exit 0
fi

USER_FLAG="$1"

if [ -z "$USER_FLAG" ]; then
  echo "使い方: ./verify.sh 'FLAG{取得した値}'   (状態を見るなら ./verify.sh --status)"
  exit 1
fi

ACTUAL=$(remote 'cat /var/lib/db-watchdog/flag.txt' | tr -d '\r\n' || true)

if [ -z "$ACTUAL" ]; then
  echo "NG: まだ成果物がありません。APIの3つの機能が揃って通っていません。"
  exit 1
fi

AGE=$(remote 'echo $(( $(date +%s) - $(stat -c %Y /var/lib/db-watchdog/flag.txt) ))')
if [ "$AGE" -gt 45 ]; then
  echo "NG: 成果物が${AGE}秒前から更新されていません。また失敗し始めています。"
  exit 1
fi

if [ "$USER_FLAG" = "$ACTUAL" ]; then
  echo "正解! $USER_FLAG"
  echo "  レポートAPIが復旧しました。"
  exit 0
else
  echo "不正解: そのFLAGは今動いているサーバのものと一致しません。"
  exit 1
fi
