FROM alpine:3.20

# 診断に使う道具一式(namei は util-linux)
RUN apk add --no-cache util-linux

RUN addgroup -g 1000 appgroup && adduser -u 1000 -G appgroup -D appuser \
 && addgroup -g 3000 analysts && addgroup appuser analysts \
 && addgroup -g 3001 secretgrp \
 && addgroup -g 3002 othergroup && adduser -u 1001 -G othergroup -D otheruser

COPY job.sh /job.sh
RUN chmod +x /job.sh

USER appuser

CMD ["sleep", "infinity"]
