#!/bin/bash
# 日次集計バッチ。cronから毎分呼ばれる想定。
set -e

# 本体の設置場所。設定ファイルの位置をここから解決する。
: "${BATCH_HOME:?BATCH_HOME が設定されていません}"

CONF="$BATCH_HOME/etc/batch.conf"
if [ ! -f "$CONF" ]; then
  echo "設定ファイルが見つかりません: $CONF (BATCH_HOME=$BATCH_HOME)" >&2
  exit 1
fi
# shellcheck disable=SC1090
. "$CONF"

: "${RETENTION_DAYS:?RETENTION_DAYS が設定ファイルにありません}"

# 集計コマンドはPATH経由で解決する
VALUE=$(reportcalc)

mkdir -p /var/lib/batch
printf '{"value": %s, "retention_days": %s, "at": "%s"}\n' \
  "$VALUE" "$RETENTION_DAYS" "$(date -Iseconds)" > /var/lib/batch/result.json

echo "$(date -Iseconds) 集計を完了しました (value=$VALUE)"
