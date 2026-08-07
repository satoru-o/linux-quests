#!/bin/sh
set -e
docker rm -f quest01-port-blocker > /dev/null 2>&1 || true
docker compose down -v > /dev/null 2>&1 || true
echo "cleaned up."
