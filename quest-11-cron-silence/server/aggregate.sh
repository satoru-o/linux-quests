#!/bin/bash
# 日次集計バッチ。cronから毎分呼ばれる想定。
set -e

: "${BATCH_HOME:?BATCH_HOME が設定されていません}"

VALUE=$(reportcalc)

mkdir -p /var/lib/batch
printf '{"value": %s, "at": "%s"}\n' "$VALUE" "$(date -Iseconds)" > /var/lib/batch/result.json

echo "$(date -Iseconds) 集計を完了しました (value=$VALUE)"
