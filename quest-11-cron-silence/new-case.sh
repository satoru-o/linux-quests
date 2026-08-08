#!/bin/sh
# サーバを立ち上げ、ランダムに1つ障害を注入する。
# 何が仕込まれたかは表示しない。SSHで入って原因を突き止め、復旧させること。
#
#   ./new-case.sh            ランダムに1つ
#   ./new-case.sh <障害ID>   指定した障害
set -e

cd "$(dirname "$0")"

CASES="cron-stopped path-missing not-executable percent-unescaped env-missing wrong-schedule"

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
  ssh-keygen -t ed25519 -N '' -C 'quest11' -f ssh/id_ed25519 > /dev/null
  chmod 600 ssh/id_ed25519
fi

echo "前の状態を片付けています..."
docker compose down -v > /dev/null 2>&1 || true

echo "サーバを起動しています..."
docker compose up -d --build > /dev/null 2>&1

i=0
while [ "$i" -lt 60 ]; do
  if docker compose exec -T server systemctl is-active batch-watchdog > /dev/null 2>&1; then
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

echo "障害を注入しています..."
case "$CASE" in
  cron-stopped)
    docker compose exec -T server systemctl stop cron
    ;;
  path-missing)
    docker compose exec -T server bash -c 'cat > /etc/cron.d/batch <<EOF
BATCH_HOME=/opt/batch

* * * * * root /opt/batch/aggregate.sh >> /var/log/batch/cron.log 2>&1
EOF
chmod 644 /etc/cron.d/batch'
    ;;
  not-executable)
    docker compose exec -T server chmod -x /opt/batch/aggregate.sh
    ;;
  percent-unescaped)
    docker compose exec -T server bash -c 'cat > /etc/cron.d/batch <<EOF
PATH=/opt/batch/bin:/usr/local/bin:/usr/bin:/bin
BATCH_HOME=/opt/batch

* * * * * root date +%Y-%m-%d >> /var/log/batch/run.log && /opt/batch/aggregate.sh >> /var/log/batch/cron.log 2>&1
EOF
chmod 644 /etc/cron.d/batch'
    ;;
  env-missing)
    docker compose exec -T server bash -c 'cat > /etc/cron.d/batch <<EOF
PATH=/opt/batch/bin:/usr/local/bin:/usr/bin:/bin

* * * * * root /opt/batch/aggregate.sh >> /var/log/batch/cron.log 2>&1
EOF
chmod 644 /etc/cron.d/batch'
    ;;
  wrong-schedule)
    docker compose exec -T server bash -c 'cat > /etc/cron.d/batch <<EOF
PATH=/opt/batch/bin:/usr/local/bin:/usr/bin:/bin
BATCH_HOME=/opt/batch

0 3 * * * root /opt/batch/aggregate.sh >> /var/log/batch/cron.log 2>&1
EOF
chmod 644 /etc/cron.d/batch'
    ;;
esac

# 直前の正常な実行結果が残っていると症状が出ないので消しておく
docker compose exec -T server bash -c 'rm -f /var/lib/batch/result.json /var/lib/batch/flag.txt /var/log/batch/cron.log'

printf 'CASE_HASH=%s\n' "$(printf '%s' "$CASE" | sha256sum | cut -d' ' -f1)" > .state
chmod 600 .state

cat <<'EOF'

--------------------------------------------------------------------
運用チームから連絡が来ている。

  「日次集計の結果が今朝から更新されていません。
    サーバには入れます。cronで毎分回っているはずなんですが……」

サーバにログインして、原因を突き止めて復旧させること。

  ssh -i ssh/id_ed25519 -p 2223 \
    -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    ec2-user@localhost

  (ec2-user は sudo が使える)

集計が定期的に走るようになると、成果物が現れる。

  cat /var/lib/batch/flag.txt

手元に戻ってから答え合わせ。

  ./verify.sh --status        今の状態を見る
  ./verify.sh 'FLAG{...}'     取得したFLAGを判定する

注意: 手で1回叩いて結果を作っても「復旧」にはならない。
      cronから定期的に走る状態にすること。
--------------------------------------------------------------------
EOF
