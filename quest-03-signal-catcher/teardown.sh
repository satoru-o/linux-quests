#!/bin/sh
set -e
rm -f flag.txt
docker compose down -v > /dev/null 2>&1 || true
echo "cleaned up."
