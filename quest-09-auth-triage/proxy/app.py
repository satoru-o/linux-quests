import os

import requests
from flask import Flask, Response, request

app = Flask(__name__)

UPSTREAM = os.environ.get("UPSTREAM", "http://api:8080")
STRIP_AUTH = os.environ.get("STRIP_AUTH", "0") == "1"


@app.get("/reports")
def forward():
    headers = {}
    auth = request.headers.get("Authorization")
    if auth and not STRIP_AUTH:
        headers["Authorization"] = auth

    resp = requests.get(f"{UPSTREAM}/reports", headers=headers, timeout=5)
    return Response(resp.content, status=resp.status_code, content_type=resp.headers.get("Content-Type", "application/json"))


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
