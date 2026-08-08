FROM python:3.12-alpine

# アプリの実行と、症例の仕込み(iptables)と、診断の道具
RUN apk add --no-cache iproute2 curl iptables su-exec tcpdump

RUN addgroup -S appgroup && adduser -S appuser -G appgroup
RUN touch /flag.txt && chown appuser:appgroup /flag.txt

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY --chown=appuser:appgroup app.py .
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 8080

# iptablesを入れるためにrootで起動し、アプリはappuserに落として実行する
CMD ["/entrypoint.sh"]
