#!/bin/sh
# ランダムに1つ故障を仕込んで、新しい症例を立ち上げる。
# 何が仕込まれたかは表示しない。診断して ./answer.sh で申告すること。
set -e

cd "$(dirname "$0")"

CASES="no-credential wrong-scheme token-expired wrong-audience bad-signature revoked-token insufficient-scope proxy-strips-header"

pick_case() {
  n=$(echo "$CASES" | wc -w)
  r=$(od -An -N2 -tu2 < /dev/urandom | tr -d ' ')
  i=$((r % n + 1))
  echo "$CASES" | cut -d' ' -f"$i"
}

CASE="${1:-$(pick_case)}"

if ! echo " $CASES " | grep -q " $CASE "; then
  echo "不明な症例: $CASE"
  exit 1
fi

echo "前の症例を片付けています..."
docker compose down -v > /dev/null 2>&1 || true

{
  echo "services:"
  echo "  fixture:"
  echo "    environment:"
  echo "      CASE: \"$CASE\""
  case "$CASE" in
    no-credential)
      echo "  client:"
      echo "    environment:"
      echo "      SEND_AUTH: \"0\""
      ;;
    wrong-scheme)
      echo "  client:"
      echo "    environment:"
      echo "      AUTH_SCHEME: \"Token\""
      ;;
    proxy-strips-header)
      echo "  proxy:"
      echo "    environment:"
      echo "      STRIP_AUTH: \"1\""
      ;;
  esac
} > docker-compose.override.yml

echo "新しい症例を用意しています..."
docker compose up -d --build > /dev/null 2>&1

# APIが応答を返せるようになるまで待つ。起動待ちを障害と誤診しないため。
i=0
while [ "$i" -lt 40 ]; do
  if docker compose exec -T client curl -sS -o /dev/null -m 2 http://proxy:8080/reports > /dev/null 2>&1; then
    break
  fi
  i=$((i + 1))
  sleep 0.5
done

printf 'CASE_HASH=%s\n' "$(printf '%s' "$CASE" | sha256sum | cut -d' ' -f1)" > .state
chmod 600 .state

cat <<'EOF'

症例の準備ができた。

  clientコンテナからAPIを呼んで 200 が返るのが正常。

    docker compose exec client /call.sh

  今はこれが 401 か 403 で失敗する。原因を1つ突き止めて申告せよ。

    ./answer.sh --list     申告できる原因の一覧
    ./answer.sh <原因ID>   申告する

  診断の型はREADMEに書いてある。401と403は別物なので、まずそこを見ること。
EOF
