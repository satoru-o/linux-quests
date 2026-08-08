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
for stale in ("token", "revoked", "proxy-token"):
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
    "nbf": now,
    "exp": now + 3600,
}
secret = JWT_SECRET
algorithm = "HS256"
truncate = False

if CASE == "token-expired":
    claims["iat"] = now - 7200
    claims["nbf"] = now - 7200
    claims["exp"] = now - 3600
elif CASE == "wrong-audience":
    claims["aud"] = "billing-api"
elif CASE == "bad-signature":
    secret = "a-different-signing-secret"
elif CASE == "insufficient-scope":
    claims["scope"] = "reports:list"
elif CASE == "revoked-token":
    (creds / "revoked").write_text(jti + "\n")
elif CASE == "clock-skew":
    # 発行側の時計が進んでいて、まだ有効になっていない
    claims["iat"] = now + 3600
    claims["nbf"] = now + 3600
    claims["exp"] = now + 7200
elif CASE == "wrong-algorithm":
    # 受け側はHS256しか受け付けない
    algorithm = "HS512"
elif CASE == "token-truncated":
    truncate = True

token = jwt.encode(claims, secret, algorithm=algorithm)

if truncate:
    # 環境変数の切り詰めなどで、署名の部分が丸ごと欠けた状態
    token = token.rsplit(".", 1)[0]

(creds / "token").write_text(token)

# proxyが自分の資格情報で上書きする症例のために、別人格のトークンも作っておく
proxy_claims = dict(claims)
proxy_claims.update({
    "sub": "proxy-service",
    "aud": EXPECTED_AUD,
    "scope": "health:read",
    "jti": secrets.token_hex(8),
    "iat": now,
    "nbf": now,
    "exp": now + 3600,
})
(creds / "proxy-token").write_text(jwt.encode(proxy_claims, JWT_SECRET, algorithm="HS256"))

print("fixture done: ready", flush=True)
