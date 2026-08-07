FROM alpine:3.20

RUN addgroup -S appgroup && adduser -S appuser -G appgroup

COPY generate_logs.sh /generate_logs.sh
RUN chmod +x /generate_logs.sh \
    && mkdir -p /var/log/app \
    && chown -R appuser:appgroup /var/log/app

USER appuser

CMD ["/generate_logs.sh"]
