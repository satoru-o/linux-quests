FROM alpine:3.20

RUN apk add --no-cache curl jq

COPY call.sh /call.sh
COPY decode.sh /decode.sh
RUN chmod +x /call.sh /decode.sh

CMD ["sleep", "infinity"]
