FROM alpine:3.20

# work側と同じUID/GIDで揃えておく(ズレると所有者の見え方が変わる)
RUN addgroup -g 1000 appgroup && adduser -u 1000 -G appgroup -D appuser \
 && addgroup -g 3000 analysts && addgroup appuser analysts \
 && addgroup -g 3001 secretgrp \
 && addgroup -g 3002 othergroup && adduser -u 1001 -G othergroup -D otheruser

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

CMD ["/entrypoint.sh"]
