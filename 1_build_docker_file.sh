#!/bin/bash
set -e

IMAGE="ado-agent:latest"
DOCKER_DIR="."

docker build -t "$IMAGE" -f "$DOCKER_DIR/Dockerfile" "$DOCKER_DIR"

SIZE=$(docker images "$IMAGE" --format="{{.Size}}")
echo "Image built: $IMAGE | Size: $SIZE"
