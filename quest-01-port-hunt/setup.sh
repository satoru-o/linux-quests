#!/bin/sh
# このクエストの前提条件(先にポート8080を占有している邪魔者)を自動セットアップする。
set -e

NAME=quest01-port-blocker

if docker ps --format '{{.Names}}' | grep -qx "$NAME"; then
  echo "prerequisite already running: $NAME"
  exit 0
fi

echo "starting prerequisite container that occupies port 8080..."
docker run -d --name "$NAME" -p 8080:80 nginx:alpine > /dev/null
echo "done. port 8080 is now occupied by '$NAME'."
