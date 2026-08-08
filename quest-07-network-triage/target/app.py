import os
import secrets
import time
from pathlib import Path

from flask import Flask, jsonify

MODE = os.environ.get("MODE", "normal")
BIND_ADDR = os.environ.get("BIND_ADDR", "0.0.0.0")
PORT = int(os.environ.get("PORT", "8080"))

# FLAGはプロセス起動時に生成する。ソースにもイメージにも固定値では存在しない。
FLAG = f"FLAG{{{secrets.token_hex(16)}}}"
Path("/flag.txt").write_text(FLAG + "\n")

app = Flask(__name__)


if MODE == "blackhole":

    @app.get("/health")
    def health():
        # 接続は受け付けるが応答を返さない
        time.sleep(3600)
        return "ok\n"

elif MODE == "error500":

    @app.get("/health")
    def health():
        return jsonify({"status": "internal server error"}), 500

elif MODE == "notfound":
    # /health を生やさない
    pass

else:

    @app.get("/health")
    def health():
        return "ok\n"


if __name__ == "__main__":
    app.run(host=BIND_ADDR, port=PORT)
