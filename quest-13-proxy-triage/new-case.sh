#!/bin/sh
# サーバを立ち上げ、ランダムに1つ障害を注入する。
# 何が仕込まれたかは表示しない。SSHで入って原因を突き止め、復旧させること。
#
#   ./new-case.sh            ランダムに1つ
#   ./new-case.sh <障害ID>   指定した障害
set -e

cd "$(dirname "$0")"

CASES="backend-down wrong-upstream-port timeout-short missing-host-header missing-proto-header config-syntax"

pick_from() {
  n=$(echo "$1" | wc -w)
  r=$(od -An -N2 -tu2 < /dev/urandom | tr -d ' ')
  i=$((r % n + 1))
  echo "$1" | cut -d' ' -f"$i"
}

CASE="${1:-$(pick_from "$CASES")}"

if ! echo " $CASES " | grep -q " $CASE "; then
  echo "不明な障害: $CASE"
  exit 1
fi

if [ ! -f ssh/id_ed25519 ]; then
  mkdir -p ssh
  ssh-keygen -t ed25519 -N '' -C 'quest13' -f ssh/id_ed25519 > /dev/null
  chmod 600 ssh/id_ed25519
fi

echo "前の状態を片付けています..."
docker compose down -v > /dev/null 2>&1 || true

echo "サーバを起動しています..."
docker compose up -d --build > /dev/null 2>&1

i=0
while [ "$i" -lt 90 ]; do
  if docker compose exec -T server curl -sS -o /dev/null -m 2 http://127.0.0.1:9001/healthz > /dev/null 2>&1; then
    break
  fi
  i=$((i + 1))
  sleep 1
done

docker compose exec -T server bash -c '
  cat > /home/ec2-user/.ssh/authorized_keys
  chown -R ec2-user:ec2-user /home/ec2-user/.ssh
  chmod 700 /home/ec2-user/.ssh
  chmod 600 /home/ec2-user/.ssh/authorized_keys
' < ssh/id_ed25519.pub

echo "構成変更を反映しています..."
case "$CASE" in
  backend-down)
    docker compose exec -T server systemctl stop backend@9002
    ;;
  wrong-upstream-port)
    docker compose exec -T server bash -c \
      "sed -i 's/127.0.0.1:9002/127.0.0.1:9012/' /etc/nginx/conf.d/reports.conf && systemctl reload nginx"
    ;;
  timeout-short)
    docker compose exec -T server bash -c \
      "sed -i 's/proxy_read_timeout 10s;/proxy_read_timeout 1s;/' /etc/nginx/conf.d/reports.conf && systemctl reload nginx"
    ;;
  missing-host-header)
    docker compose exec -T server bash -c \
      "sed -i '/proxy_set_header Host /d' /etc/nginx/conf.d/reports.conf && systemctl reload nginx"
    ;;
  missing-proto-header)
    docker compose exec -T server bash -c \
      "sed -i '/proxy_set_header X-Forwarded-Proto /d' /etc/nginx/conf.d/reports.conf && systemctl reload nginx"
    ;;
  config-syntax)
    docker compose exec -T server bash -c \
      "sed -i 's/proxy_read_timeout 10s;/proxy_read_timeout 10s/' /etc/nginx/conf.d/reports.conf; systemctl restart nginx > /dev/null 2>&1 || true"
    ;;
esac

# 起動直後の競合で出たログが残っていると紛らわしいので、ここから記録し直す
docker compose exec -T server bash -c '
  rm -f /var/lib/proxy-watchdog/flag.txt
  truncate -s 0 /var/log/nginx/access.log /var/log/nginx/error.log' || true

printf 'CASE_HASH=%s\n' "$(printf '%s' "$CASE" | sha256sum | cut -d' ' -f1)" > .state
chmod 600 .state

sleep 12

cat <<'EOF'

--------------------------------------------------------------------
監視から断続的なアラートが上がっている。

  [WARN] ip-10-0-4-25 : レポート画面でエラーが出ると問い合わせあり

このサーバは前段のnginxが3台のバックエンドへ振り分けている。
直前に構成変更が入ったらしいが、詳細は聞けていない。

サーバにログインして、原因を突き止めて復旧させること。

  ssh -i ssh/id_ed25519 -p 2225 \
    -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    ec2-user@localhost

  (ec2-user は sudo が使える)

利用者と同じ経路が安定して通るようになると、成果物が現れる。

  cat /var/lib/proxy-watchdog/flag.txt

手元に戻ってから答え合わせ。

  ./verify.sh --status        今の状態を見る
  ./verify.sh 'FLAG{...}'     取得したFLAGを判定する

注意: 1回通っただけでは復旧とみなされない。
      見張り役が繰り返し叩いて、全部通ることを確認している。
--------------------------------------------------------------------
EOF
