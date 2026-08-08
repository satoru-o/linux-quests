FROM alpine:3.20

# 診断に使う道具一式
RUN apk add --no-cache curl bind-tools iproute2 netcat-openbsd tcpdump

RUN addgroup -S probegroup && adduser -S probeuser -G probegroup

CMD ["sleep", "infinity"]
