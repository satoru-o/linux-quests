import ipaddress
import os
import secrets
import socket
import time
from pathlib import Path

from flask import Flask, jsonify, request

MODE = os.environ.get("MODE", "normal")
BIND_ADDR = os.environ.get("BIND_ADDR", "0.0.0.0")
PORT = int(os.environ.get("PORT", "8080"))
SLOW_SECONDS = int(os.environ.get("SLOW_SECONDS", "8"))
ALLOW_CIDR = os.environ.get("ALLOW_CIDR", "10.99.0.0/16")
EXPECTED_HOST = os.environ.get("EXPECTED_HOST", "reports.internal")

# FLAGはプロセス起動時に生成する。ソースにもイメージにも固定値では存在しない。
FLAG = f"FLAG{{{secrets.token_hex(16)}}}"
Path("/flag.txt").write_text(FLAG + "\n")


def serve_empty_reply():
    """接続は受け付けるが、何も返さずに即座に切る。"""
    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind((BIND_ADDR, PORT))
    srv.listen(16)
    print(f"[target] listening on {BIND_ADDR}:{PORT}", flush=True)
    while True:
        conn, addr = srv.accept()
        print(f"[target] {addr[0]} 接続直後に切断した", flush=True)
        conn.close()


app = Flask(__name__)


if MODE == "blackhole":

    @app.get("/health")
    def health():
        # 接続は受け付けるが応答を返さない
        time.sleep(3600)
        return "ok\n"

elif MODE == "slow-response":

    @app.get("/health")
    def health():
        time.sleep(SLOW_SECONDS)
        return "ok\n"

elif MODE == "error500":

    @app.get("/health")
    def health():
        return jsonify({"status": "internal server error"}), 500

elif MODE == "ip-allowlist":

    @app.get("/health")
    def health():
        src = request.remote_addr or "0.0.0.0"
        allowed = ipaddress.ip_address(src) in ipaddress.ip_network(ALLOW_CIDR)
        if not allowed:
            print(f"[target] {src} は許可レンジ({ALLOW_CIDR})外のため拒否", flush=True)
            return jsonify({"status": "forbidden"}), 403
        return "ok\n"

elif MODE == "wrong-host":

    @app.get("/health")
    def health():
        host = request.headers.get("Host", "")
        if host.split(":")[0] != EXPECTED_HOST:
            print(f"[target] Host={host} は未知のホスト名(既定の振り分け先に落ちた)", flush=True)
            return jsonify({"status": "not found"}), 404
        return "ok\n"

elif MODE == "notfound":
    # /health を生やさない
    pass

else:

    @app.get("/health")
    def health():
        return "ok\n"


if __name__ == "__main__":
    if MODE == "empty-reply":
        serve_empty_reply()
    else:
        app.run(host=BIND_ADDR, port=PORT, threaded=True)
