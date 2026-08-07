FROM python:3.12-alpine

RUN addgroup -S appgroup && adduser -S appuser -G appgroup

RUN mkdir -p /www && chown appuser:appgroup /www
WORKDIR /www

COPY --chown=appuser:appgroup serve.py ./

USER appuser
EXPOSE 8080

CMD ["python", "serve.py"]
