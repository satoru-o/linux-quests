#!/bin/sh
# サーバを立ち上げ、ランダムに1つ障害を注入する。
# 何が仕込まれたかは表示しない。SSHで入って原因を突き止め、復旧させること。
#
#   ./new-case.sh            ランダムに1つ
#   ./new-case.sh <障害ID>   指定した障害
set -e

cd "$(dirname "$0")"

CASES="bad-execstart-path not-executable wrong-user missing-workdir unit-masked missing-config"

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
  ssh-keygen -t ed25519 -N '' -C 'quest12' -f ssh/id_ed25519 > /dev/null
  chmod 600 ssh/id_ed25519
fi

echo "前の状態を片付けています..."
docker compose down -v > /dev/null 2>&1 || true

echo "サーバを起動しています..."
docker compose up -d --build > /dev/null 2>&1

i=0
while [ "$i" -lt 60 ]; do
  if docker compose exec -T server systemctl is-active orderapi > /dev/null 2>&1; then
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

echo "デプロイ作業を反映しています..."
dropin() {
  docker compose exec -T server bash -c "
    mkdir -p /etc/systemd/system/orderapi.service.d
    cat > /etc/systemd/system/orderapi.service.d/override.conf <<'DROPIN'
$1
DROPIN
    systemctl daemon-reload"
}

case "$CASE" in
  bad-execstart-path)
    dropin '[Service]
ExecStart=
ExecStart=/opt/orderapi/server.sh'
    ;;
  not-executable)
    docker compose exec -T server chmod -x /opt/orderapi/serve.sh
    ;;
  wrong-user)
    dropin '[Service]
User=orderapi-svc'
    ;;
  missing-workdir)
    dropin '[Service]
WorkingDirectory=/opt/orderapi/current'
    ;;
  unit-masked)
    docker compose exec -T server bash -c 'systemctl stop orderapi; systemctl mask orderapi' > /dev/null 2>&1
    ;;
  missing-config)
    docker compose exec -T server rm -f /etc/orderapi/app.conf
    ;;
esac

docker compose exec -T server bash -c '
  systemctl restart orderapi > /dev/null 2>&1 || true
  sleep 2
  rm -f /var/lib/orderapi/flag.txt' || true

printf 'CASE_HASH=%s\n' "$(printf '%s' "$CASE" | sha256sum | cut -d' ' -f1)" > .state
chmod 600 .state

cat <<'EOF'

--------------------------------------------------------------------
デプロイ後、監視が落ちたままになっている。

  [CRITICAL] ip-10-0-3-91 : orderapi が起動していません

直前に別のメンバーが構成変更を入れたらしいが、詳細は聞けていない。
サーバにログインして、原因を突き止めて復旧させること。

  ssh -i ssh/id_ed25519 -p 2224 \
    -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    ec2-user@localhost

  (ec2-user は sudo が使える)

サービスが動き出すと成果物が現れる。

  cat /var/lib/orderapi/flag.txt

手元に戻ってから答え合わせ。

  ./verify.sh --status        今の状態を見る
  ./verify.sh 'FLAG{...}'     取得したFLAGを判定する
--------------------------------------------------------------------
EOF
