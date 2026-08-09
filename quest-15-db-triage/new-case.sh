#!/bin/sh
# アプリサーバとDBを立ち上げ、ランダムに1つ障害を注入する。
# 何が仕込まれたかは表示しない。SSHでアプリサーバに入って原因を突き止め、復旧させること。
#
#   ./new-case.sh            初級・上級ぜんぶから1つ
#   ./new-case.sh --hard     上級だけから1つ
#   ./new-case.sh <障害ID>   指定した障害
set -e

cd "$(dirname "$0")"

BASIC="table-revoked sg-blocked conn-hog readonly-default sequence-denied lock-blocked"
HARD="index-dropped statement-timeout schema-usage-revoked search-path-changed rls-no-policy audit-trigger"

pick_from() {
  n=$(echo "$1" | wc -w)
  r=$(od -An -N2 -tu2 < /dev/urandom | tr -d ' ')
  i=$((r % n + 1))
  echo "$1" | cut -d' ' -f"$i"
}

case "$1" in
  --hard) CASE=$(pick_from "$HARD") ;;
  "")     CASE=$(pick_from "$BASIC $HARD") ;;
  *)      CASE="$1" ;;
esac

if ! echo " $BASIC $HARD " | grep -q " $CASE "; then
  echo "不明な障害: $CASE"
  exit 1
fi

if [ ! -f ssh/id_ed25519 ]; then
  mkdir -p ssh
  ssh-keygen -t ed25519 -N '' -C 'quest15' -f ssh/id_ed25519 > /dev/null
  chmod 600 ssh/id_ed25519
fi

echo "前の状態を片付けています..."
docker compose down -v > /dev/null 2>&1 || true

echo "サーバを起動しています..."
docker compose up -d --build > /dev/null 2>&1

i=0
while [ "$i" -lt 120 ]; do
  if docker compose exec -T app \
       curl -sS -o /dev/null -m 3 http://127.0.0.1:8080/api/reports > /dev/null 2>&1; then
    break
  fi
  i=$((i + 1))
  sleep 1
done

docker compose exec -T app bash -c '
  cat > /home/ec2-user/.ssh/authorized_keys
  chown -R ec2-user:ec2-user /home/ec2-user/.ssh
  chmod 700 /home/ec2-user/.ssh
  chmod 600 /home/ec2-user/.ssh/authorized_keys
' < ssh/id_ed25519.pub

dbsql() {
  docker compose exec -T db psql -q -d reportdb -c "$1" > /dev/null
}

echo "直前の変更を反映しています..."
case "$CASE" in
  table-revoked)
    dbsql "REVOKE SELECT ON app.reports FROM reportapi"
    ;;
  sg-blocked)
    docker compose exec -T app iptables -A OUTPUT -p tcp --dport 5432 -j DROP
    ;;
  conn-hog)
    # アプリの一時的な接続に枠を残さないよう、先に埋めさせてから戻す
    docker compose exec -T app bash -c \
      'systemctl stop reportapi
       systemctl start conn-hog
       sleep 4
       systemctl start reportapi'
    ;;
  readonly-default)
    dbsql "ALTER DATABASE reportdb SET default_transaction_read_only = on"
    ;;
  sequence-denied)
    dbsql "REVOKE USAGE ON SEQUENCE app.reports_id_seq FROM reportapi"
    ;;
  lock-blocked)
    docker compose exec -T app systemctl start lock-holder
    ;;
  index-dropped)
    dbsql "DROP INDEX app.idx_archive_region_created"
    ;;
  statement-timeout)
    dbsql "ALTER ROLE reportapi SET statement_timeout = '150ms'"
    ;;
  schema-usage-revoked)
    dbsql "REVOKE USAGE ON SCHEMA app FROM reportapi"
    ;;
  search-path-changed)
    dbsql "ALTER ROLE reportapi SET search_path = public"
    ;;
  rls-no-policy)
    dbsql "ALTER TABLE app.reports ENABLE ROW LEVEL SECURITY"
    ;;
  audit-trigger)
    docker compose exec -T db psql -q -d reportdb > /dev/null <<'SQL'
CREATE OR REPLACE FUNCTION app.audit_reports() RETURNS trigger AS $$
BEGIN
  INSERT INTO app.audit_log(what) VALUES ('report ' || NEW.id);
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER trg_audit_reports AFTER INSERT ON app.reports
  FOR EACH ROW EXECUTE FUNCTION app.audit_reports();
SQL
    ;;
esac

# 起動直後の競合で出たログが残っていると紛らわしいので、ここから記録し直す
docker compose exec -T app bash -c '
  rm -f /var/lib/db-watchdog/flag.txt
  systemctl restart db-watchdog' || true

printf 'CASE_HASH=%s\n' "$(printf '%s' "$CASE" | sha256sum | cut -d' ' -f1)" > .state
chmod 600 .state

sleep 15

cat <<'EOF'

--------------------------------------------------------------------
監視からアラートが上がっている。

  [CRITICAL] ip-10-0-1-42 : レポートAPIの死活監視が失敗

  アプリサーバ  ip-10-0-1-42    (ここにSSHで入れる)
  DB            ip-10-0-101-7   reportdb.internal:5432

DBは別インスタンスで、SSHは通っていない。psqlでしか触れない。
直前にDB周りで何か変更が入ったらしいが、詳細は聞けていない。

アプリサーバにログインして、原因を突き止めて復旧させること。

  ssh -i ssh/id_ed25519 -p 2227 \
    -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    ec2-user@localhost

  (ec2-user は sudo が使える。保守用の接続情報は /opt/reportdb/ にある)

APIの3つの機能が揃って通るようになると、成果物が現れる。

  cat /var/lib/db-watchdog/flag.txt

手元に戻ってから答え合わせ。

  ./verify.sh --status        今の状態を見る
  ./verify.sh 'FLAG{...}'     取得したFLAGを判定する

注意: 一覧が200で返るだけでは復旧ではない。
      登録と集計も通す必要がある。
--------------------------------------------------------------------
EOF
