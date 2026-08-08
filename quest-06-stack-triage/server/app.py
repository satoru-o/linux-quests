import json
import os
import secrets
from pathlib import Path

from flask import Flask, jsonify

app = Flask(__name__)

# FLAGはプロセス起動時にメモリ上で生成する。ソースにもファイルにも固定値では存在しない。
FLAG_REACH = f"FLAG{{{secrets.token_hex(16)}}}"
FLAG_REPORT = f"FLAG{{{secrets.token_hex(16)}}}"

BIND_ADDR = os.environ.get("BIND_ADDR", "127.0.0.1")
REPORT_PATH = Path("/reports/report.json")


@app.get("/")
def root():
    return FLAG_REACH + "\n"


@app.get("/data")
def data():
    # clientが集計するための元データ
    records = [
        {"endpoint": f"/api/resource{i % 5}", "ms": (i * 37) % 400}
        for i in range(200)
    ]
    return jsonify({"records": records})


@app.get("/report")
def report():
    try:
        payload = json.loads(REPORT_PATH.read_text())
    except FileNotFoundError:
        return jsonify({"status": "no-report", "detail": f"{REPORT_PATH} がまだ存在しない"}), 404
    except PermissionError as e:
        return jsonify({"status": "unreadable", "detail": str(e)}), 403
    return jsonify({"status": "ok", "summary": payload.get("summary"), "flag": FLAG_REPORT})


if __name__ == "__main__":
    app.run(host=BIND_ADDR, port=8080)
