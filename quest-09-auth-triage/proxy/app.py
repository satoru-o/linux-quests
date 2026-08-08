import os
from pathlib import Path

import requests
from flask import Flask, Response, request

app = Flask(__name__)

UPSTREAM = os.environ.get("UPSTREAM", "http://api:8080")
STRIP_AUTH = os.environ.get("STRIP_AUTH", "0") == "1"
OVERWRITE_AUTH = os.environ.get("OVERWRITE_AUTH", "0") == "1"
PROXY_TOKEN_PATH = Path("/creds/proxy-token")


@app.get("/reports")
def forward():
    headers = {}
    auth = request.headers.get("Authorization")

    if OVERWRITE_AUTH:
        # 自分のサービスアカウントで上書きしてしまう
        try:
            headers["Authorization"] = f"Bearer {PROXY_TOKEN_PATH.read_text().strip()}"
        except FileNotFoundError:
            pass
    elif auth and not STRIP_AUTH:
        headers["Authorization"] = auth

    resp = requests.get(f"{UPSTREAM}/reports", headers=headers, timeout=5)
    out = Response(resp.content, status=resp.status_code,
                   content_type=resp.headers.get("Content-Type", "application/json"))
    if "Retry-After" in resp.headers:
        out.headers["Retry-After"] = resp.headers["Retry-After"]
    return out


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
