# Docker Deployment

This project includes a Docker configuration to run both the Flutter frontend and Python backend server in a containerized environment.

## Prerequisites

1. Docker installed on your system
2. A Google Gemini API key

## Starting a Local Registry

If you don't already have a local Docker registry running, you can start one with the provided script:

```bash
./start_registry.sh
```

This will start a Docker registry on port 5000, which is required for the build script.

To stop the registry when you're done:

```bash
./stop_registry.sh
```

## Building the Docker Image

To build the Docker image for Intel 64-bit architecture, run:

```bash
docker buildx build --progress=plain --platform linux/amd64 -t learnlm-app .
```

## Building and Pushing to Local Registry

A convenient build script is provided that will build the image with the obfuscated API key and push it to your local registry:

```bash
GEMINI_API_KEY=your_actual_api_key_here ./build_docker.sh
```

This will:
1. Build the Docker image with the provided API key for Intel 64-bit architecture
2. Obfuscate the API key using base64 encoding with chunking
3. Compile all Python files to .pyc bytecode
4. Remove source files, leaving only compiled bytecode
5. Tag the image as localhost:5000/learn
6. Push the image to your local registry

## Running with Docker

1. Create a `.env` file in the project root with your API key:
   ```
   GEMINI_API_KEY=your_actual_api_key_here
   ```

2. Run the container:
   ```bash
   docker run -p 8035:8035 --env-file .env learnlm-app
   ```

Or if you used the build script:
```bash
docker run -p 8035:8035 localhost:5000/learn
```

## Running with Docker Compose

1. Create a `.env` file in the project root with your API key and optional password:
   ```
   GEMINI_API_KEY=your_actual_api_key_here
   APP_PASSWORD=your_optional_password_here
   ```

2. Run with docker-compose:
   ```bash
   docker-compose up
   ```

## API Key Obfuscation

For production deployments, the Docker build process automatically obfuscates the API key using base64 encoding with chunking. This provides a simple layer of obfuscation to prevent the API key from being easily visible in the source code.

The obfuscation process:
1. Takes the GEMINI_API_KEY environment variable during build
2. Generates a Python module (ky.py) with the base64-encoded key split into 2-character chunks
3. Compiles all Python files to .pyc bytecode
4. Removes the original source files, leaving only the compiled bytecode

This approach ensures that:
- The API key is not visible in the source code
- Only compiled bytecode files are deployed
- The application can still access the API key at runtime

## Accessing the Application

Once running, you can access the application at:
- Web interface: http://localhost:8035
- REST API: http://localhost:8035/api/chat/completion
- WebSocket API: ws://localhost:8035/api/chat/completion/stream

## Two-Stage Build Process

The Dockerfile uses a two-stage build process:

1. **Flutter Build Stage**: Uses a Debian image to build the Flutter web application
2. **Server Stage**: Uses a Python slim image to run the backend server with the built frontend

This approach minimizes the final image size while ensuring all dependencies are properly handled.