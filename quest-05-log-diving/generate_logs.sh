#!/bin/sh
# FLAGはこのスクリプト実行のたびに/dev/urandomから生成される。ソースには固定値として存在しない。
LOGFILE=/var/log/app/access.log
mkdir -p /var/log/app

FLAG="FLAG{$(head -c 16 /dev/urandom | md5sum | cut -d' ' -f1)}"
FLAG_LINE=$((RANDOM % 3000 + 500))
i=0
while [ "$i" -lt 4000 ]; do
  i=$((i + 1))
  if [ "$i" -eq "$FLAG_LINE" ]; then
    echo "$(date -Iseconds) 10.0.0.$((i % 255)) GET /secret-endpoint 200 $FLAG" >> "$LOGFILE"
  else
    echo "$(date -Iseconds) 10.0.0.$((i % 255)) GET /api/resource$((i % 50)) 200 OK" >> "$LOGFILE"
  fi
done

tail -f /dev/null
