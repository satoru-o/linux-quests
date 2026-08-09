#!/bin/bash
# ビルド時に一式の証明書を作る。
#   /opt/tls              運用で使う正規のPKI資材
#   /usr/local/lib/quest-fixtures  障害注入用の差し替え資材
set -e

PKI=/opt/tls
FIX=/usr/local/lib/quest-fixtures
mkdir -p "$PKI" "$FIX"
cd "$PKI"

leaf_ext() {
  cat <<EXT
basicConstraints=CA:FALSE
keyUsage=critical,digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth
subjectAltName=DNS:$1
EXT
}

# --- ルートCA ---
openssl req -x509 -newkey rsa:2048 -nodes -sha256 -days 3650 \
  -keyout rootCA.key -out rootCA.crt \
  -subj "/CN=Reports Root CA" \
  -addext "basicConstraints=critical,CA:TRUE" 2>/dev/null

# --- 中間CA(ルートが署名) ---
openssl req -newkey rsa:2048 -nodes -sha256 \
  -keyout intermediate.key -out intermediate.csr \
  -subj "/CN=Reports Intermediate CA" 2>/dev/null
printf 'basicConstraints=critical,CA:TRUE,pathlen:0\nkeyUsage=critical,keyCertSign,cRLSign\n' > inter.ext
openssl x509 -req -in intermediate.csr -CA rootCA.crt -CAkey rootCA.key \
  -CAcreateserial -out intermediate.crt -days 3650 -sha256 -extfile inter.ext 2>/dev/null

# --- サーバ証明書(中間CAが署名) ---
openssl req -newkey rsa:2048 -nodes -sha256 \
  -keyout server.key -out server.csr -subj "/CN=reports.internal" 2>/dev/null
leaf_ext reports.internal > leaf.ext
openssl x509 -req -in server.csr -CA intermediate.crt -CAkey intermediate.key \
  -CAcreateserial -out server.crt -days 825 -sha256 -extfile leaf.ext 2>/dev/null
cat server.crt intermediate.crt > fullchain.crt

# --- 以下は障害注入用 ---

# 期限切れ(過去の日付で発行する)
faketime '2023-01-01 00:00:00' openssl req -newkey rsa:2048 -nodes -sha256 \
  -keyout "$FIX/expired.key" -out "$FIX/expired.csr" -subj "/CN=reports.internal" 2>/dev/null
faketime '2023-01-01 00:00:00' openssl x509 -req -in "$FIX/expired.csr" \
  -CA intermediate.crt -CAkey intermediate.key -CAcreateserial \
  -out "$FIX/expired.crt" -days 30 -sha256 -extfile leaf.ext 2>/dev/null
cat "$FIX/expired.crt" intermediate.crt > "$FIX/expired-fullchain.crt"

# 別のホスト名向け
openssl req -newkey rsa:2048 -nodes -sha256 \
  -keyout "$FIX/wrongsan.key" -out "$FIX/wrongsan.csr" -subj "/CN=other.internal" 2>/dev/null
leaf_ext other.internal > wrongsan.ext
openssl x509 -req -in "$FIX/wrongsan.csr" -CA intermediate.crt -CAkey intermediate.key \
  -CAcreateserial -out "$FIX/wrongsan.crt" -days 825 -sha256 -extfile wrongsan.ext 2>/dev/null
cat "$FIX/wrongsan.crt" intermediate.crt > "$FIX/wrongsan-fullchain.crt"

# 自己署名
openssl req -x509 -newkey rsa:2048 -nodes -sha256 -days 825 \
  -keyout "$FIX/selfsigned.key" -out "$FIX/selfsigned.crt" \
  -subj "/CN=reports.internal" \
  -addext "subjectAltName=DNS:reports.internal" 2>/dev/null

# 対応しない鍵
openssl genrsa -out "$FIX/other.key" 2048 2>/dev/null

# サーバ証明書だけ(中間CAを含まない)
cp server.crt "$FIX/leaf-only.crt"

rm -f *.csr *.ext "$FIX"/*.csr
chmod 640 "$PKI"/*.key
chmod 600 "$FIX"/*.key
