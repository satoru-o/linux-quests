FROM python:3.12-alpine

# 調査に使う道具は最初から入れてある
RUN apk add --no-cache iproute2 curl

RUN addgroup -g 2000 -S srvgroup && adduser -u 2000 -S srvuser -G srvgroup

# レポートを置く共有ディレクトリ。誰でも書き込める(/tmpと同じ1777)
RUN mkdir -p /reports && chmod 1777 /reports

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY --chown=srvuser:srvgroup app.py .

USER srvuser
EXPOSE 8080

CMD ["python", "app.py"]
