import os
import socket
import time

from flask import Flask, jsonify, redirect, request

PORT = int(os.environ.get("PORT", "9001"))
EXPECTED_HOST = os.environ.get("EXPECTED_HOST", "reports.internal")

app = Flask(__name__)


def client_ip():
    # プロキシ越しの本当の送信元は X-Forwarded-For の先頭
    xff = request.headers.get("X-Forwarded-For", "")
    return xff.split(",")[0].strip() if xff else request.remote_addr


def log(status, note=""):
    print(f"[backend:{PORT}] {request.method} {request.path} "
          f"host={request.headers.get('Host')} "
          f"xfp={request.headers.get('X-Forwarded-Proto')} "
          f"client={client_ip()} -> {status} {note}", flush=True)


@app.get("/healthz")
def healthz():
    # 死活確認用。振り分けの条件は見ない
    return "ok\n"


def guard():
    """Hostとプロトコルの前提を確認する。問題があれば応答を返す。"""
    if (request.headers.get("Host") or "").split(":")[0] != EXPECTED_HOST:
        log(404, "未知のホスト名")
        return jsonify({"error": "not found"}), 404
    if request.headers.get("X-Forwarded-Proto") != "https":
        # 暗号化されていない扱いになるので、同じURLへ張り替える
        log(301, "X-Forwarded-Proto が https ではない")
        return redirect(request.url, code=301)
    return None


@app.get("/api/report")
def report():
    bad = guard()
    if bad:
        return bad
    log(200)
    return jsonify({"served_by": f"{socket.gethostname()}:{PORT}", "report": "2026-08"})


@app.get("/api/slow")
def slow():
    bad = guard()
    if bad:
        return bad
    time.sleep(3)
    log(200, "(3秒かかる処理)")
    return jsonify({"served_by": f"{socket.gethostname()}:{PORT}", "slow": True})


if __name__ == "__main__":
    app.run(host="127.0.0.1", port=PORT, threaded=True)
