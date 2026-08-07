#!/bin/sh
set -e
docker compose down -v > /dev/null 2>&1 || true
echo "cleaned up."
