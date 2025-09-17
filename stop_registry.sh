#!/bin/bash

# stop_registry.sh - Stop the local Docker registry

# Check if registry is running
if ! docker ps | grep -q registry; then
    echo "Local registry is not running"
    exit 0
fi

echo "Stopping local Docker registry..."
docker stop registry
docker rm registry

echo "Local registry stopped and removed"