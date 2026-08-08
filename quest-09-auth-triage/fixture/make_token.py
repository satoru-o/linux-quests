import os
import secrets
import time
from pathlib import Path

import jwt

CASE = os.environ.get("CASE", "normal")
JWT_SECRET = os.environ.get("JWT_SECRET", "dojo-signing-secret")
EXPECTED_AUD = os.environ.get("EXPECTED_AUD", "reports-api")
REQUIRED_SCOPE = os.environ.get("REQUIRED_SCOPE", "reports:read")

creds = Path("/creds")
creds.mkdir(parents=True, exist_ok=True)
for stale in ("token", "revoked"):
    (creds / stale).unlink(missing_ok=True)

# FLAGはこのコンテナ内で都度生成する。共有ボリュームには置かない。
flag_path = Path("/flag.txt")
if not flag_path.exists() or not flag_path.read_text().strip():
    flag_path.write_text(f"FLAG{{{secrets.token_hex(16)}}}\n")

now = int(time.time())
jti = secrets.token_hex(8)

claims = {
    "sub": "analyst",
    "aud": EXPECTED_AUD,
    "scope": REQUIRED_SCOPE,
    "jti": jti,
    "iat": now,
    "exp": now + 3600,
}
secret = JWT_SECRET

if CASE == "token-expired":
    claims["iat"] = now - 7200
    claims["exp"] = now - 3600
elif CASE == "wrong-audience":
    claims["aud"] = "billing-api"
elif CASE == "bad-signature":
    secret = "a-different-signing-secret"
elif CASE == "insufficient-scope":
    claims["scope"] = "reports:list"
elif CASE == "revoked-token":
    (creds / "revoked").write_text(jti + "\n")

token = jwt.encode(claims, secret, algorithm="HS256")
(creds / "token").write_text(token)

print("fixture done: ready", flush=True)
