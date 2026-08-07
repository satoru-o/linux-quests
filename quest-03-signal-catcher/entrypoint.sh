#!/bin/sh
# FLAGはSIGTERMを受け取った瞬間に初めて生成される。それまではどこにも存在しない。
trap 'FLAG="FLAG{$(head -c 16 /dev/urandom | md5sum | cut -d" " -f1)}"; echo "$FLAG" > /flag.txt; exit 0' TERM

echo "waiting for a graceful signal..."
while true; do
  sleep 1
done
