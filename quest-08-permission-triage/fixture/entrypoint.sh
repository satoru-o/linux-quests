#!/bin/sh
# 症例に応じて /data の権限まわりを組み立てる。rootで一度だけ走る。
set -e

CASE="${CASE:-normal}"

# FLAGはこのコンテナ内で都度生成する。共有ボリュームには置かない。
if [ ! -s /flag.txt ]; then
  printf 'FLAG{%s}\n' "$(head -c 16 /dev/urandom | md5sum | cut -d' ' -f1)" > /flag.txt
fi

# --- 前の症例の痕跡を消す ---
chattr -R -i /data 2>/dev/null || true
setfacl -R -b /data 2>/dev/null || true
chmod 0755 /data
rm -rf /data/out.txt /data/report.txt /data/old.txt /data/run.sh /data/.private /data/filler

# --- 正常な状態を組む ---
echo "売上レポート 2026-08" > /data/report.txt
chown root:analysts /data/report.txt
chmod 640 /data/report.txt

echo "先月の作業ファイル" > /data/old.txt
chown appuser:appgroup /data/old.txt
chmod 644 /data/old.txt

printf '#!/bin/sh\necho "集計スクリプトを実行した"\n' > /data/run.sh
chown appuser:appgroup /data/run.sh
chmod 755 /data/run.sh

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
  acl-deny)
    # モードは誰でも読めるように見えるが、ACLで個別に拒否する
    chown root:analysts /data/report.txt
    chmod 644 /data/report.txt
    setfacl -m u:appuser:--- /data/report.txt
    ;;
  immutable-attr)
    # 所有者もモードも問題ないのに書けない
    echo "" > /data/out.txt
    chown appuser:appgroup /data/out.txt
    chmod 644 /data/out.txt
    chattr +i /data/out.txt
    ;;
  no-exec-bit)
    chmod 644 /data/run.sh
    ;;
  noexec-mount)
    # マウント側(compose)で noexec にするので、ここでは何もしない
    :
    ;;
  symlink-denied)
    mkdir -p /data/.private
    chown root:root /data/.private
    chmod 755 /data/.private
    echo "売上レポート 2026-08" > /data/.private/real.txt
    chown root:root /data/.private/real.txt
    chmod 600 /data/.private/real.txt
    rm -f /data/report.txt
    ln -s .private/real.txt /data/report.txt
    ;;
  uid-unmapped)
    # このコンテナに存在しないUIDが所有者になっている(ホストとのUIDズレ)
    chown 1500:1500 /data/report.txt
    chmod 600 /data/report.txt
    ;;
  normal)
    :
    ;;
esac

echo "fixture done: ready"
