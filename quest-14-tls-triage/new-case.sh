#!/bin/sh
# サーバを立ち上げ、ランダムに1つ障害を注入する。
# 何が仕込まれたかは表示しない。SSHで入って原因を突き止め、復旧させること。
#
#   ./new-case.sh            ランダムに1つ
#   ./new-case.sh <障害ID>   指定した障害
set -e

cd "$(dirname "$0")"

CASES="cert-expired wrong-san missing-chain ca-untrusted key-mismatch self-signed"

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
  ssh-keygen -t ed25519 -N '' -C 'quest14' -f ssh/id_ed25519 > /dev/null
  chmod 600 ssh/id_ed25519
fi

echo "前の状態を片付けています..."
docker compose down -v > /dev/null 2>&1 || true

echo "サーバを起動しています..."
docker compose up -d --build > /dev/null 2>&1

i=0
while [ "$i" -lt 90 ]; do
  if docker compose exec -T server systemctl is-active nginx > /dev/null 2>&1; then
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

echo "証明書の入れ替え作業を反映しています..."
FIX=/usr/local/lib/quest-fixtures
case "$CASE" in
  cert-expired)
    docker compose exec -T server bash -c "
      cp $FIX/expired-fullchain.crt /etc/nginx/tls/server.crt
      cp $FIX/expired.key /etc/nginx/tls/server.key
      chmod 640 /etc/nginx/tls/server.key
      systemctl reload nginx"
    ;;
  wrong-san)
    docker compose exec -T server bash -c "
      cp $FIX/wrongsan-fullchain.crt /etc/nginx/tls/server.crt
      cp $FIX/wrongsan.key /etc/nginx/tls/server.key
      chmod 640 /etc/nginx/tls/server.key
      systemctl reload nginx"
    ;;
  missing-chain)
    docker compose exec -T server bash -c "
      cp $FIX/leaf-only.crt /etc/nginx/tls/server.crt
      systemctl reload nginx"
    ;;
  ca-untrusted)
    docker compose exec -T server bash -c "
      rm -f /usr/local/share/ca-certificates/reports-root.crt
      update-ca-certificates --fresh > /dev/null 2>&1"
    ;;
  key-mismatch)
    docker compose exec -T server bash -c "
      cp $FIX/other.key /etc/nginx/tls/server.key
      chmod 640 /etc/nginx/tls/server.key
      systemctl restart nginx > /dev/null 2>&1 || true"
    ;;
  self-signed)
    docker compose exec -T server bash -c "
      cp $FIX/selfsigned.crt /etc/nginx/tls/server.crt
      cp $FIX/selfsigned.key /etc/nginx/tls/server.key
      chmod 640 /etc/nginx/tls/server.key
      systemctl reload nginx"
    ;;
esac

docker compose exec -T server bash -c '
  rm -f /var/lib/tls-watchdog/flag.txt
  truncate -s 0 /var/log/nginx/access.log /var/log/nginx/error.log' || true

printf 'CASE_HASH=%s\n' "$(printf '%s' "$CASE" | sha256sum | cut -d' ' -f1)" > .state
chmod 600 .state

sleep 12

cat <<'EOF'

--------------------------------------------------------------------
監視からアラートが上がっている。

  [CRITICAL] ip-10-0-5-14 : https://reports.internal への接続が検証に失敗

証明書の入れ替え作業が入ったらしいが、詳細は聞けていない。
サーバにログインして、原因を突き止めて復旧させること。

  ssh -i ssh/id_ed25519 -p 2226 \
    -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    ec2-user@localhost

  (ec2-user は sudo が使える)

検証つきの接続が通るようになると、成果物が現れる。

  cat /var/lib/tls-watchdog/flag.txt

手元に戻ってから答え合わせ。

  ./verify.sh --status        今の状態を見る
  ./verify.sh 'FLAG{...}'     取得したFLAGを判定する

注意: curl -k で通ることは復旧ではない。検証を通すのがゴール。
--------------------------------------------------------------------
EOF
