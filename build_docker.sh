#!/bin/bash

# build_docker.sh - Build and push Docker image to local registry

# Check if GEMINI_API_KEY is set
if [ -z "$GEMINI_API_KEY" ]; then
    echo "Error: GEMINI_API_KEY environment variable is not set"
    echo "Usage: GEMINI_API_KEY=your_api_key_here ./build_docker.sh"
    exit 1
fi

# Set variables
IMAGE_NAME="learn"
LOCAL_REGISTRY="localhost:5000"
FULL_IMAGE_NAME="${LOCAL_REGISTRY}/${IMAGE_NAME}"

echo "Building Docker image: ${IMAGE_NAME}"
echo "Target registry: ${LOCAL_REGISTRY}"

# Build the Docker image with the API key for Intel 64-bit architecture
GEMINI_API_KEY="$GEMINI_API_KEY" docker buildx build --progress=plain --platform linux/amd64 --build-arg GEMINI_API_KEY="$GEMINI_API_KEY" --load -t "$IMAGE_NAME" .

# Check if build was successful
if [ $? -ne 0 ]; then
    echo "Error: Docker build failed"
    exit 1
fi

echo "Tagging image for local registry: ${FULL_IMAGE_NAME}"
docker tag "$IMAGE_NAME" "$FULL_IMAGE_NAME" 2>/dev/null || {
    echo "Warning: Could not tag image. This may be because the image was loaded directly."
}

echo "Pushing image to local registry: ${FULL_IMAGE_NAME}"
docker push "$FULL_IMAGE_NAME"

# Check if push was successful
if [ $? -ne 0 ]; then
    echo "Error: Failed to push image to registry"
    exit 1
fi

echo "Successfully built and pushed image to ${FULL_IMAGE_NAME}"
echo "To run the image:"
echo "  docker run -p 8035:8035 ${FULL_IMAGE_NAME}"