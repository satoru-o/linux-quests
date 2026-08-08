#!/bin/sh
# ランダムに1つ故障を仕込んで、新しい症例を立ち上げる。
# 何が仕込まれたかは表示しない。診断して ./answer.sh で申告すること。
set -e

cd "$(dirname "$0")"

CASES="not-owner group-not-member no-read-bit dir-no-exec dir-no-read dir-no-write sticky-other readonly-mount"

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
  if [ "$CASE" = "readonly-mount" ]; then
    echo "  work:"
    echo "    volumes: !override"
    echo "      - data:/data:ro"
  fi
} > docker-compose.override.yml

echo "新しい症例を用意しています..."
docker compose up -d --build > /dev/null 2>&1

printf 'CASE_HASH=%s\n' "$(printf '%s' "$CASE" | sha256sum | cut -d' ' -f1)" > .state
chmod 600 .state

cat <<'EOF'

症例の準備ができた。

  workコンテナの中で appuser として /data の定常業務を回すのが正常。

    docker compose exec work /job.sh

  今はどれかの操作が失敗する。原因を1つ突き止めて申告せよ。

    ./answer.sh --list     申告できる原因の一覧
    ./answer.sh <原因ID>   申告する

  診断の型はREADMEに書いてある。"Permission denied" を見た瞬間に
  ファイルのモードだけを疑うのが典型的な誤診なので注意。
EOF
