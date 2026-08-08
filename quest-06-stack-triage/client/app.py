import json
import os
import secrets
import time
from pathlib import Path

import requests

SERVER_URL = os.environ.get("SERVER_URL", "http://server:8080")
REPORT_PATH = Path("/reports/report.json")

# FLAGはプロセス起動時にメモリ上で生成する。serverとの疎通に成功したときだけログに出す。
FLAG_RELAY = f"FLAG{{{secrets.token_hex(16)}}}"

announced = False

while True:
    try:
        resp = requests.get(f"{SERVER_URL}/data", timeout=3)
        resp.raise_for_status()
        records = resp.json()["records"]
    except requests.exceptions.RequestException as e:
        print(f"[client] serverに到達できない: {e}", flush=True)
        time.sleep(3)
        continue

    if not announced:
        print(f"[client] serverへの接続に成功: {FLAG_RELAY}", flush=True)
        announced = True

    summary = {}
    for r in records:
        summary[r["endpoint"]] = summary.get(r["endpoint"], 0) + 1

    REPORT_PATH.write_text(json.dumps({"summary": summary}))
    # レポートは秘匿情報なので厳しめの権限にしておく
    os.chmod(REPORT_PATH, 0o600)

    print(f"[client] レポートを書き出した: {REPORT_PATH}", flush=True)
    time.sleep(10)
