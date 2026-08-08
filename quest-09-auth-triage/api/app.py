import os
from pathlib import Path

import jwt
from flask import Flask, jsonify, request

app = Flask(__name__)

JWT_SECRET = os.environ.get("JWT_SECRET", "dojo-signing-secret")
EXPECTED_AUD = os.environ.get("EXPECTED_AUD", "reports-api")
REQUIRED_SCOPE = os.environ.get("REQUIRED_SCOPE", "reports:read")
RATE_LIMIT = os.environ.get("RATE_LIMIT", "0") == "1"
REVOKED_PATH = Path("/creds/revoked")


def log(received, result):
    # サーバ側には「何が届いたか」を残す。診断ではここを見るのが定石。
    print(f"[api] GET /reports auth={received} -> {result}", flush=True)


def revoked_ids():
    try:
        return {line.strip() for line in REVOKED_PATH.read_text().splitlines() if line.strip()}
    except FileNotFoundError:
        return set()


@app.get("/healthz")
def healthz():
    # 起動確認用。診断の邪魔にならないようログには残さない
    return "ok\n"


@app.get("/reports")
def reports():
    header = request.headers.get("Authorization")

    if not header:
        log("(なし)", "401 認証情報なし")
        return jsonify({"error": "unauthorized"}), 401

    shown = f'"{header[:24]}..."'

    parts = header.split(" ", 1)
    if len(parts) != 2 or parts[0] != "Bearer":
        log(shown, "401 スキームがBearerではない")
        return jsonify({"error": "unauthorized"}), 401

    token = parts[1]

    try:
        claims = jwt.decode(
            token,
            JWT_SECRET,
            algorithms=["HS256"],
            audience=EXPECTED_AUD,
        )
    except (jwt.InvalidSignatureError, jwt.InvalidAlgorithmError):
        # 鍵が違う場合も、想定外のアルゴリズムの場合もここに来る
        log(shown, "401 署名検証に失敗")
        return jsonify({"error": "unauthorized"}), 401
    except (jwt.ExpiredSignatureError, jwt.InvalidAudienceError, jwt.ImmatureSignatureError):
        log(shown, "401 クレーム検証に失敗")
        return jsonify({"error": "unauthorized"}), 401
    except jwt.PyJWTError:
        log(shown, "401 トークンの形式が不正")
        return jsonify({"error": "unauthorized"}), 401

    if claims.get("jti") in revoked_ids():
        log(shown, "401 失効済みトークン")
        return jsonify({"error": "unauthorized"}), 401

    sub = claims.get("sub", "?")
    scopes = claims.get("scope", "").split()
    if REQUIRED_SCOPE not in scopes:
        # 誰かは分かっているが、その操作は許されていない
        log(shown, f"403 スコープ不足 sub={sub}")
        return jsonify({"error": "forbidden"}), 403

    if RATE_LIMIT:
        log(shown, f"429 レート制限 sub={sub}")
        resp = jsonify({"error": "too many requests"})
        resp.headers["Retry-After"] = "60"
        return resp, 429

    log(shown, f"200 ok sub={sub}")
    return jsonify({"status": "ok", "reports": ["2026-06", "2026-07", "2026-08"]})


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
