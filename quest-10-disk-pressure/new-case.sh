#!/bin/sh
# サーバを立ち上げ、ランダムに1つ障害を注入する。
# 何が仕込まれたかは表示しない。SSHで入って原因を突き止め、復旧させること。
#
#   ./new-case.sh            ランダムに1つ
#   ./new-case.sh <障害ID>   指定した障害
set -e

cd "$(dirname "$0")"

CASES="big-log deleted-open inode-exhausted many-rotated runaway-writer"

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

# SSHの鍵は初回だけ作る(git管理外)
if [ ! -f ssh/id_ed25519 ]; then
  mkdir -p ssh
  ssh-keygen -t ed25519 -N '' -C 'quest10' -f ssh/id_ed25519 > /dev/null
  chmod 600 ssh/id_ed25519
fi

echo "前の状態を片付けています..."
docker compose down -v > /dev/null 2>&1 || true

echo "サーバを起動しています..."
docker compose up -d --build > /dev/null 2>&1

# systemdが上がりきるまで待つ
i=0
while [ "$i" -lt 60 ]; do
  if docker compose exec -T server systemctl is-active reportd > /dev/null 2>&1; then
    break
  fi
  i=$((i + 1))
  sleep 1
done

# 公開鍵を配置する
docker compose exec -T server bash -c '
  cat > /home/ec2-user/.ssh/authorized_keys
  chown -R ec2-user:ec2-user /home/ec2-user/.ssh
  chmod 700 /home/ec2-user/.ssh
  chmod 600 /home/ec2-user/.ssh/authorized_keys
' < ssh/id_ed25519.pub

echo "障害を注入しています..."
case "$CASE" in
  big-log)
    docker compose exec -T server bash -c '
      dd if=/dev/zero of=/var/log/reportd/access.log.old bs=1M count=64 2>/dev/null || true'
    ;;
  deleted-open)
    # 領域を埋めたうえで、掴まれているログを消す(空きが戻らない状態を作る)
    docker compose exec -T server bash -c '
      dd if=/dev/zero of=/var/log/reportd/app.log bs=1M count=64 2>/dev/null || true
      rm -f /var/log/reportd/app.log'
    ;;
  inode-exhausted)
    docker compose exec -T server bash -c '
      mkdir -p /var/log/reportd/spool
      for i in $(seq 1 2100); do : > /var/log/reportd/spool/msg-$i.tmp 2>/dev/null || break; done' 2>/dev/null || true
    ;;
  many-rotated)
    docker compose exec -T server bash -c '
      for i in $(seq 1 40); do dd if=/dev/zero of=/var/log/reportd/app.log.$i.gz bs=1M count=1 2>/dev/null || break; done' 2>/dev/null || true
    ;;
  runaway-writer)
    docker compose exec -T server bash -c '
      dd if=/dev/zero of=/var/log/reportd/debug-metrics.bin bs=1M count=24 2>/dev/null || true
      systemctl start debug-collector' || true
    ;;
esac

printf 'CASE_HASH=%s\n' "$(printf '%s' "$CASE" | sha256sum | cut -d' ' -f1)" > .state
chmod 600 .state

sleep 8

cat <<'EOF'

--------------------------------------------------------------------
監視からアラートが上がっている。

  [CRITICAL] ip-10-0-1-42 : reportd がレポートを書き出せていません

サーバにログインして、原因を突き止めて復旧させること。

  ssh -i ssh/id_ed25519 -p 2222 \
    -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    ec2-user@localhost

  (ec2-user は sudo が使える)

復旧すると reportd が成果物を書き出すようになる。

  cat /var/lib/reportd/flag.txt

手元に戻ってから答え合わせ。

  ./verify.sh --status        今の状態を見る
  ./verify.sh 'FLAG{...}'     取得したFLAGを判定する
--------------------------------------------------------------------
EOF
