import os
import requests
from flask import Flask, jsonify

app = Flask(__name__)
DB_HOST = os.environ.get("DB_HOST", "db")


@app.get("/check")
def check():
    try:
        resp = requests.get(f"http://{DB_HOST}/flag", timeout=2)
        return jsonify({"status": "ok", "flag": resp.text})
    except requests.exceptions.RequestException as e:
        return jsonify({"status": "error", "detail": str(e), "db_host": DB_HOST}), 502


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
