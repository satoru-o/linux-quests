#!/bin/sh
set -e
cd "$(dirname "$0")"
docker compose run --rm --no-deps --entrypoint sh fixture -c 'chattr -R -i /data 2>/dev/null; setfacl -R -b /data 2>/dev/null; true' > /dev/null 2>&1 || true
docker compose down -v > /dev/null 2>&1 || true
rm -f .state docker-compose.override.yml
echo "cleaned up."
