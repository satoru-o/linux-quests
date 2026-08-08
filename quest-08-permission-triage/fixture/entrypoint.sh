#!/bin/sh
# 症例に応じて /data の権限まわりを組み立てる。rootで一度だけ走る。
set -e

CASE="${CASE:-normal}"

# FLAGはこのコンテナ内で都度生成する。共有ボリュームには置かない。
if [ ! -s /flag.txt ]; then
  printf 'FLAG{%s}\n' "$(head -c 16 /dev/urandom | md5sum | cut -d' ' -f1)" > /flag.txt
fi

# --- まず正常な状態を組む ---
chmod 0755 /data
rm -rf /data/out.txt /data/report.txt /data/old.txt

echo "売上レポート 2026-08" > /data/report.txt
chown root:analysts /data/report.txt
chmod 640 /data/report.txt

echo "先月の作業ファイル" > /data/old.txt
chown appuser:appgroup /data/old.txt
chmod 644 /data/old.txt

chown root:analysts /data
chmod 775 /data

# --- 症例を適用する ---
case "$CASE" in
  not-owner)
    chown root:root /data/report.txt
    chmod 600 /data/report.txt
    ;;
  group-not-member)
    chown root:secretgrp /data/report.txt
    chmod 640 /data/report.txt
    ;;
  no-read-bit)
    chown appuser:appgroup /data/report.txt
    chmod 200 /data/report.txt
    ;;
  dir-no-exec)
    chmod 744 /data
    ;;
  dir-no-read)
    chmod 711 /data
    ;;
  dir-no-write)
    chmod 755 /data
    ;;
  sticky-other)
    chmod 1777 /data
    chown otheruser:othergroup /data/old.txt
    ;;
  readonly-mount)
    # マウント側(compose)で ro にするので、ここでは何もしない
    :
    ;;
  normal)
    :
    ;;
esac

echo "fixture done: ready"
