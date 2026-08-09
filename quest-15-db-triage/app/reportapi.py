#!/usr/bin/env python3
"""レポートAPI。リクエストごとにDBへ接続する。

DBから返ったエラーはそのまま500の本文とログに出す。
"""
import json
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import psycopg2

CONF_PATH = "/etc/reportapi/app.conf"
LISTEN = ("127.0.0.1", 8080)

SUMMARY_SQL = """
SELECT t.region,
       (SELECT coalesce(sum(a.amount), 0)
          FROM reports_archive a
         WHERE a.region = t.region
           AND a.created_at >= now() - interval '7 days') AS total
  FROM report_targets t
 ORDER BY t.region
"""

LIST_SQL = "SELECT id, region, amount FROM reports ORDER BY id DESC LIMIT 5"
INSERT_SQL = "INSERT INTO reports(region, amount) VALUES (%s, %s) RETURNING id"
BUMP_SQL = "UPDATE counters SET n = n + 1 WHERE name = 'reports'"


def load_conf(path):
    conf = {}
    with open(path) as fh:
        for line in fh:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            key, _, value = line.partition("=")
            conf[key.strip()] = value.strip()
    return conf


CFG = load_conf(CONF_PATH)


def connect():
    return psycopg2.connect(
        host=CFG["DB_HOST"],
        port=CFG["DB_PORT"],
        dbname=CFG["DB_NAME"],
        user=CFG["DB_USER"],
        password=CFG["DB_PASSWORD"],
        connect_timeout=5,
        application_name="reportapi",
    )


def with_conn(fn):
    """接続を張り、必ず閉じる。psycopg2のwith文はトランザクションしか面倒を見ない。"""
    conn = connect()
    try:
        with conn.cursor() as cur:
            return fn(conn, cur)
    finally:
        conn.close()


def list_reports():
    def run(_conn, cur):
        cur.execute(LIST_SQL)
        rows = [{"id": r[0], "region": r[1], "amount": r[2]} for r in cur.fetchall()]
        return 200, {"count": len(rows), "rows": rows}
    return with_conn(run)


def create_report():
    def run(conn, cur):
        cur.execute(INSERT_SQL, ("r-01", 100))
        new_id = cur.fetchone()[0]
        cur.execute(BUMP_SQL)
        conn.commit()
        return 201, {"id": new_id}
    return with_conn(run)


def summary():
    def run(_conn, cur):
        cur.execute(SUMMARY_SQL)
        rows = [{"region": r[0], "total": int(r[1])} for r in cur.fetchall()]
        return 200, {"count": len(rows), "rows": rows}
    return with_conn(run)


ROUTES = {
    ("GET", "/api/reports"): list_reports,
    ("POST", "/api/reports"): create_report,
    ("GET", "/api/summary"): summary,
}


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def _dispatch(self, method):
        handler = ROUTES.get((method, self.path))
        if handler is None:
            self._send(404, {"error": "not found"})
            return
        try:
            status, payload = handler()
        except psycopg2.Error as exc:
            message = (str(exc) or exc.__class__.__name__).strip()
            print(f"[reportapi] {method} {self.path} DBエラー: {message}",
                  file=sys.stderr, flush=True)
            self._send(500, {"error": message})
            return
        except Exception as exc:  # noqa: BLE001
            print(f"[reportapi] {method} {self.path} 想定外のエラー: {exc}",
                  file=sys.stderr, flush=True)
            self._send(500, {"error": str(exc)})
            return
        self._send(status, payload)

    def do_GET(self):
        self._dispatch("GET")

    def do_POST(self):
        length = int(self.headers.get("Content-Length") or 0)
        if length:
            self.rfile.read(length)
        self._dispatch("POST")

    def _send(self, status, payload):
        body = json.dumps(payload, ensure_ascii=False).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt, *args):
        print(f"[reportapi] {fmt % args}", file=sys.stderr, flush=True)


if __name__ == "__main__":
    ThreadingHTTPServer(LISTEN, Handler).serve_forever()
