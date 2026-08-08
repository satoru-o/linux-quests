#!/bin/sh
# ランダムに1つ故障を仕込んで、新しい症例を立ち上げる。
# 何が仕込まれたかは表示しない。診断して ./answer.sh で申告すること。
#
#   ./new-case.sh            初級から1つ
#   ./new-case.sh --hard     上級から1つ
#   ./new-case.sh --all      初級+上級から1つ
#   ./new-case.sh <原因ID>   指定した症例
set -e

cd "$(dirname "$0")"

BASIC="process-down bind-localhost wrong-port network-split wrong-address blackhole app-error app-notfound"
HARD="firewall-drop firewall-reject slow-response empty-reply ip-allowlist wrong-host"

pick_from() {
  n=$(echo "$1" | wc -w)
  r=$(od -An -N2 -tu2 < /dev/urandom | tr -d ' ')
  i=$((r % n + 1))
  echo "$1" | cut -d' ' -f"$i"
}

case "${1:-}" in
  --hard) CASE=$(pick_from "$HARD") ;;
  --all)  CASE=$(pick_from "$BASIC $HARD") ;;
  "")     CASE=$(pick_from "$BASIC") ;;
  *)      CASE="$1" ;;
esac

if ! echo " $BASIC $HARD " | grep -q " $CASE "; then
  echo "不明な症例: $CASE"
  exit 1
fi

write_override() {
  case "$1" in
    bind-localhost)  printf 'services:\n  target:\n    environment:\n      BIND_ADDR: "127.0.0.1"\n' ;;
    wrong-port)      printf 'services:\n  target:\n    environment:\n      PORT: "9090"\n' ;;
    blackhole)       printf 'services:\n  target:\n    environment:\n      MODE: "blackhole"\n' ;;
    app-error)       printf 'services:\n  target:\n    environment:\n      MODE: "error500"\n' ;;
    app-notfound)    printf 'services:\n  target:\n    environment:\n      MODE: "notfound"\n' ;;
    slow-response)   printf 'services:\n  target:\n    environment:\n      MODE: "slow-response"\n' ;;
    empty-reply)     printf 'services:\n  target:\n    environment:\n      MODE: "empty-reply"\n' ;;
    ip-allowlist)    printf 'services:\n  target:\n    environment:\n      MODE: "ip-allowlist"\n' ;;
    wrong-host)      printf 'services:\n  target:\n    environment:\n      MODE: "wrong-host"\n' ;;
    firewall-drop)   printf 'services:\n  target:\n    environment:\n      FIREWALL: "drop"\n' ;;
    firewall-reject) printf 'services:\n  target:\n    environment:\n      FIREWALL: "reject"\n' ;;
    network-split)   printf 'services:\n  probe:\n    networks: !override\n      - isolated\n\nnetworks:\n  isolated:\n' ;;
    wrong-address)   printf 'services:\n  probe:\n    extra_hosts:\n      - "target:10.255.255.10"\n' ;;
    *)               printf 'services: {}\n' ;;
  esac
}

echo "前の症例を片付けています..."
docker compose down -v > /dev/null 2>&1 || true

write_override "$CASE" > docker-compose.override.yml

echo "新しい症例を用意しています..."
docker compose up -d --build > /dev/null 2>&1

# アプリが起動しきる前に触ると、ただの起動待ちを「接続できない」と誤診してしまう。
# listenが始まるまで待ってから症例を渡す。
i=0
while [ "$i" -lt 40 ]; do
  if docker compose exec -T target sh -c 'ss -tln | grep -q LISTEN' > /dev/null 2>&1; then
    break
  fi
  i=$((i + 1))
  sleep 0.5
done

if [ "$CASE" = "process-down" ]; then
  docker compose stop target > /dev/null 2>&1
fi

printf 'CASE_HASH=%s\n' "$(printf '%s' "$CASE" | sha256sum | cut -d' ' -f1)" > .state
chmod 600 .state

cat <<'EOF'

症例の準備ができた。

  正常なら、probeコンテナから以下が 200 と "ok" を返すはず。

    docker compose exec probe curl -sS -m 5 http://target:8080/health

  今はそれが失敗する。原因を1つ突き止めて申告せよ。

    ./answer.sh --list     申告できる原因の一覧
    ./answer.sh <原因ID>   申告する

  診断の型と、カテゴリ別のコマンド集はREADMEにある。
  上の層から当てずっぽうに触らず、下から順に潰すこと。
EOF
