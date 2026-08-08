FROM python:3.12-alpine

RUN apk add --no-cache iproute2 curl

RUN addgroup -S appgroup && adduser -S appuser -G appgroup
RUN touch /flag.txt && chown appuser:appgroup /flag.txt

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY --chown=appuser:appgroup app.py .

USER appuser

CMD ["python", "app.py"]
