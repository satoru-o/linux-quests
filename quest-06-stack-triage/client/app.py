import json
import os
import secrets
import socket
import time
from pathlib import Path
from urllib.parse import urlparse

import requests

SERVER_URL = os.environ.get("SERVER_URL", "http://server:8080")
SERVER_HOST = urlparse(SERVER_URL).hostname
REPORT_PATH = Path("/reports/report.json")

# FLAGはプロセス起動時にメモリ上で生成する。serverの名前を引けたときだけログに出す。
FLAG_RELAY = f"FLAG{{{secrets.token_hex(16)}}}"

resolved = False

while True:
    # まず名前解決だけを試す
    try:
        addr = socket.gethostbyname(SERVER_HOST)
    except socket.gaierror as e:
        print(f"[client] '{SERVER_HOST}' の名前が引けない: {e}", flush=True)
        time.sleep(3)
        continue

    if not resolved:
        print(f"[client] '{SERVER_HOST}' の名前を引けた ({addr}): {FLAG_RELAY}", flush=True)
        resolved = True

    # 名前が引けたうえで、実際に接続してデータを取りにいく
    try:
        resp = requests.get(f"{SERVER_URL}/data", timeout=3)
        resp.raise_for_status()
        records = resp.json()["records"]
    except requests.exceptions.RequestException as e:
        print(f"[client] 名前は引けたが接続できない ({addr}): {e}", flush=True)
        time.sleep(3)
        continue

    summary = {}
    for r in records:
        summary[r["endpoint"]] = summary.get(r["endpoint"], 0) + 1

    REPORT_PATH.write_text(json.dumps({"summary": summary}))
    # レポートは秘匿情報なので厳しめの権限にしておく
    os.chmod(REPORT_PATH, 0o600)

    print(f"[client] レポートを書き出した: {REPORT_PATH}", flush=True)
    time.sleep(10)
