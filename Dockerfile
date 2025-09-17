# Multi-stage build for Flutter frontend, API key generation, and Python server runtime

# Define build arguments
ARG TARGETPLATFORM

# Stage 1: Build the Flutter frontend
FROM --platform=$TARGETPLATFORM debian:bullseye AS flutter-build

# Install dependencies
RUN apt-get update && apt-get install -y \
    curl \
    git \
    unzip \
    xz-utils \
    zip \
    libglu1-mesa \
    && rm -rf /var/lib/apt/lists/*

# Create a non-root user for Flutter
RUN useradd -m -u 1000 user

# Install Flutter SDK
ENV FLUTTER_HOME=/home/user/flutter
RUN curl -O https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.35.4-stable.tar.xz && \
    mkdir /home/user/flutter && \
    tar -xf flutter_linux_3.35.4-stable.tar.xz -C /home/user/flutter --strip-components=1 && \
    rm flutter_linux_3.35.4-stable.tar.xz
ENV PATH="$FLUTTER_HOME/bin:$FLUTTER_HOME/bin/cache/dart-sdk/bin:$PATH"

# Set working directory
WORKDIR /app

# Copy Flutter project files needed for dependency resolution
COPY learnlm/pubspec.yaml ./learnlm/
WORKDIR /app/learnlm

# Change ownership of copied files to the non-root user
RUN chown -R user:user /app && \
    chown -R user:user /home/user/flutter

# Switch to non-root user
USER user

# Download dependencies (skip precache as it hangs in Docker)
RUN flutter -v pub get

# Copy the rest of the Flutter project
WORKDIR /app
COPY learnlm/. ./learnlm/
RUN find ./learnlm -name "pubspec.lock" -delete

# Change ownership of copied files to the non-root user
RUN ls -l /app/

# Clean the project to remove platform-specific files
WORKDIR /app/learnlm
RUN flutter clean

# Build the Flutter web app
WORKDIR /app/learnlm
RUN flutter build web --release --no-tree-shake-icons --no-wasm-dry-run

# Stage 2: Build Python environment, generate API key module, and compile sources
FROM --platform=$TARGETPLATFORM python:3.11-slim AS python-build

ENV VENV_PATH=/opt/venv
RUN python -m venv $VENV_PATH
ENV PATH="$VENV_PATH/bin:$PATH"

RUN apt-get update && apt-get install -y --no-install-recommends bash && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /build
COPY server ./server
COPY generate_api_key.sh ./generate_api_key.sh

RUN pip install --no-cache-dir -r server/requirements.txt

ARG GEMINI_API_KEY
ENV GEMINI_API_KEY=${GEMINI_API_KEY:-placeholder}
RUN chmod +x ./generate_api_key.sh && ./generate_api_key.sh

WORKDIR /build/server
RUN $VENV_PATH/bin/python -m compileall -b src && \
    find src -name "__pycache__" -type d -exec rm -rf {} + && \
    find src -name "*.py" -type f -delete

# Stage 3: Runtime image with pre-built assets and virtual environment
FROM --platform=$TARGETPLATFORM python:3.11-slim

ENV VENV_PATH=/opt/venv
COPY --from=python-build $VENV_PATH $VENV_PATH
ENV PATH="$VENV_PATH/bin:$PATH"

RUN useradd --create-home --shell /bin/bash app
WORKDIR /home/app/app

COPY --from=python-build /build/server/src ./src
COPY --from=flutter-build /app/learnlm/build/web ./learnlm/build/web

ENV DATABASE_PATH=/home/app/app/data/chats.db
RUN mkdir -p /home/app/app/data && \
    chown -R app:app /home/app/app && \
    PYVER=$($VENV_PATH/bin/python -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")') && \
    echo "/home/app/app" > $VENV_PATH/lib/python${PYVER}/site-packages/app.pth

USER app

ENV PYTHONPATH=/home/app/app

CMD ["python", "-m", "src.main", "-d", "learnlm/build/web", "--database", "/home/app/app/data/chats.db"]
