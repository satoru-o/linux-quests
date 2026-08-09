#!/usr/bin/env python3
"""トランザクションを開いたまま放置するバッチ。行ロックを握り続ける。"""
import sys
import time

import psycopg2

conn = psycopg2.connect(
    host="reportdb.internal", port=5432, dbname="reportdb",
    user="batchuser", password="batchuser_pw",
    connect_timeout=5, application_name="nightly-recalc",
)
cur = conn.cursor()
cur.execute("UPDATE app.counters SET n = n + 1 WHERE name = 'reports'")

print("[nightly-recalc] 集計処理を開始しました", file=sys.stderr, flush=True)

# コミットもロールバックもしないまま待ち続ける
while True:
    time.sleep(3600)
