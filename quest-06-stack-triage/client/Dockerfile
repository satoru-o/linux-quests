FROM python:3.12-alpine

# 調査に使う道具は最初から入れてある
RUN apk add --no-cache iproute2 curl bind-tools

RUN addgroup -g 2001 -S cligroup && adduser -u 2001 -S cliuser -G cligroup

# レポートを置く共有ディレクトリ。誰でも書き込める(/tmpと同じ1777)
RUN mkdir -p /reports && chmod 1777 /reports

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY --chown=cliuser:cligroup app.py .

USER cliuser

CMD ["python", "app.py"]
