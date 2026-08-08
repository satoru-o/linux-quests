#!/bin/sh
# 症例によってはパケットフィルタを入れてからアプリを起動する。
set -e

PORT="${PORT:-8080}"

case "${FIREWALL:-none}" in
  drop)
    # SYNを黙って捨てる。送信側からは「無反応」に見える
    iptables -A INPUT -p tcp --dport "$PORT" -j DROP
    ;;
  reject)
    # RSTを返して即座に拒否する。送信側からは「接続拒否」に見える
    iptables -A INPUT -p tcp --dport "$PORT" -j REJECT --reject-with tcp-reset
    ;;
esac

exec su-exec appuser python app.py
