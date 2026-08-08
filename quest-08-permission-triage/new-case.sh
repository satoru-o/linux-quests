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

BASIC="not-owner group-not-member no-read-bit dir-no-exec dir-no-read dir-no-write sticky-other readonly-mount"
HARD="acl-deny immutable-attr no-exec-bit noexec-mount symlink-denied uid-unmapped"

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

echo "前の症例を片付けています..."
# immutable属性が残っているとボリュームごと消せないので、先に解除する
docker compose run --rm --no-deps --entrypoint sh fixture \
  -c 'chattr -R -i /data 2>/dev/null; setfacl -R -b /data 2>/dev/null; true' > /dev/null 2>&1 || true
docker compose down -v > /dev/null 2>&1 || true

{
  echo "services:"
  echo "  fixture:"
  echo "    environment:"
  echo "      CASE: \"$CASE\""
  case "$CASE" in
    readonly-mount)
      echo "  work:"
      echo "    volumes: !override"
      echo "      - data:/data:ro"
      ;;
    noexec-mount)
      echo "  work:"
      echo "    cap_add:"
      echo "      - SYS_ADMIN"
      ;;
  esac
} > docker-compose.override.yml

echo "新しい症例を用意しています..."
docker compose up -d --build > /dev/null 2>&1

if [ "$CASE" = "noexec-mount" ]; then
  # マウントオプションはコンテナ内でしか変えられないので、rootで入って付け替える
  docker compose exec -T -u root work mount -o remount,noexec /data > /dev/null 2>&1 || true
fi

printf 'CASE_HASH=%s\n' "$(printf '%s' "$CASE" | sha256sum | cut -d' ' -f1)" > .state
chmod 600 .state

cat <<'EOF'

症例の準備ができた。

  workコンテナの中で appuser として /data の定常業務を回すのが正常。

    docker compose exec work /job.sh

  今はどれかの操作が失敗する。原因を1つ突き止めて申告せよ。

    ./answer.sh --list     申告できる原因の一覧
    ./answer.sh <原因ID>   申告する

  診断の型と、カテゴリ別のコマンド集はREADMEにある。
  "Permission denied" を見た瞬間にファイルのモードだけを疑うのが典型的な誤診。
EOF
