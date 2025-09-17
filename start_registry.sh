#!/bin/bash

# start_registry.sh - Start a local Docker registry

# Check if registry is already running
if docker ps | grep -q registry; then
    echo "Local registry is already running"
    exit 0
fi

echo "Starting local Docker registry on port 5000..."
docker run -d -p 5000:5000 --name registry registry:2

if [ $? -eq 0 ]; then
    echo "Local registry started successfully"
    echo "You can now use the build_docker.sh script to build and push images"
else
    echo "Failed to start local registry"
    exit 1
fi