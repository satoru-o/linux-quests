#!/bin/sh
# ランダムに1つ故障を仕込んで、新しい症例を立ち上げる。
# 何が仕込まれたかは表示しない。診断して ./answer.sh で申告すること。
set -e

cd "$(dirname "$0")"

CASES="process-down bind-localhost wrong-port network-split wrong-address blackhole app-error app-notfound"

pick_case() {
  n=$(echo "$CASES" | wc -w)
  r=$(od -An -N2 -tu2 < /dev/urandom | tr -d ' ')
  i=$((r % n + 1))
  echo "$CASES" | cut -d' ' -f"$i"
}

write_override() {
  case "$1" in
    bind-localhost)
      cat > docker-compose.override.yml <<'EOF'
services:
  target:
    environment:
      BIND_ADDR: "127.0.0.1"
EOF
      ;;
    wrong-port)
      cat > docker-compose.override.yml <<'EOF'
services:
  target:
    environment:
      PORT: "9090"
EOF
      ;;
    network-split)
      cat > docker-compose.override.yml <<'EOF'
services:
  probe:
    networks: !override
      - isolated

networks:
  isolated:
EOF
      ;;
    wrong-address)
      cat > docker-compose.override.yml <<'EOF'
services:
  probe:
    extra_hosts:
      - "target:10.255.255.10"
EOF
      ;;
    blackhole)
      cat > docker-compose.override.yml <<'EOF'
services:
  target:
    environment:
      MODE: "blackhole"
EOF
      ;;
    app-error)
      cat > docker-compose.override.yml <<'EOF'
services:
  target:
    environment:
      MODE: "error500"
EOF
      ;;
    app-notfound)
      cat > docker-compose.override.yml <<'EOF'
services:
  target:
    environment:
      MODE: "notfound"
EOF
      ;;
    *)
      # process-down は構成としては正常。起動後にプロセスを止める
      cat > docker-compose.override.yml <<'EOF'
services: {}
EOF
      ;;
  esac
}

CASE="${1:-$(pick_case)}"

if ! echo " $CASES " | grep -q " $CASE "; then
  echo "不明な症例: $CASE"
  exit 1
fi

echo "前の症例を片付けています..."
docker compose down -v > /dev/null 2>&1 || true

write_override "$CASE"

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

  診断の型はREADMEに書いてある。上の層から当てずっぽうに触らず、下から順に潰すこと。
EOF
