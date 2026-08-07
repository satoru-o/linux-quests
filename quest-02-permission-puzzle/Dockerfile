FROM alpine:3.20

RUN addgroup -S appgroup && adduser -S appuser -G appgroup
RUN addgroup -S flaggroup

# FLAGはビルド時に/dev/urandomから都度生成する。このファイルのどこにも固定値としては存在しない。
RUN mkdir -p /secret \
    && FLAG="FLAG{$(head -c 16 /dev/urandom | md5sum | cut -d' ' -f1)}" \
    && echo "$FLAG" > /secret/flag.txt \
    && chown root:flaggroup /secret/flag.txt \
    && chmod 640 /secret/flag.txt

USER appuser
WORKDIR /home/appuser

CMD ["sleep", "infinity"]
