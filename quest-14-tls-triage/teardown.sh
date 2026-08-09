#!/bin/sh
set -e
cd "$(dirname "$0")"
docker compose down -v > /dev/null 2>&1 || true
rm -f .state docker-compose.override.yml
echo "cleaned up. (SSHの鍵は ssh/ に残してある)"
