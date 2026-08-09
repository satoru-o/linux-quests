#!/usr/bin/env python3
"""接続を握ったまま離さないバッチ。空きスロットを埋め、空けばまた埋める。"""
import sys
import time

import psycopg2

MAX = 60
conns = []


def open_one():
    conn = psycopg2.connect(
        host="reportdb.internal", port=5432, dbname="reportdb",
        user="batchuser", password="batchuser_pw",
        connect_timeout=3, application_name="batch-loader",
    )
    conn.autocommit = True
    return conn


def alive(conn):
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT 1")
        return True
    except psycopg2.Error:
        try:
            conn.close()
        except psycopg2.Error:
            pass
        return False


held = -1
while True:
    conns = [c for c in conns if alive(c)]
    while len(conns) < MAX:
        try:
            conns.append(open_one())
        except psycopg2.Error:
            break
    if len(conns) != held:
        held = len(conns)
        print(f"[batch-loader] {held} 本の接続を保持しています",
              file=sys.stderr, flush=True)
    time.sleep(0.5)
