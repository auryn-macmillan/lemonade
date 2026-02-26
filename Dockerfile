# ==============================================================
# # 1. Build stage — compile lemonade C++ binaries
# # ============================================================
FROM ubuntu:24.04 AS builder

# Avoid interactive prompts during build
ENV DEBIAN_FRONTEND=noninteractive

# Install build dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    cmake \
    ninja-build \
    libssl-dev \
    pkg-config \
    git \
    && rm -rf /var/lib/apt/lists/*

# Copy source code
COPY . /app
WORKDIR /app

# Build the project
RUN rm -rf build && \
    cmake --preset default && \
    cmake --build --preset default

# Debug: Check build outputs
RUN echo "=== Build directory contents ===" && \
    ls -la build/ && \
    echo "=== Checking for resources ===" && \
    find build/ -name "*.json" -o -name "resources" -type d

# # ============================================================
# # 2. Runtime stage — small, clean image
# # ============================================================
FROM ubuntu:24.04

# Install runtime dependencies only
RUN apt-get update && apt-get install -y \
    libcurl4 \
    curl \
    libssl3 \
    zlib1g \
    vulkan-tools \
    libvulkan1 \
    unzip \
    libgomp1 \
    && rm -rf /var/lib/apt/lists/*

# Create application directory
WORKDIR /opt/lemonade

# Copy built executables and resources from builder
COPY --from=builder /app/build/lemonade-router ./lemonade-router
COPY --from=builder /app/build/lemonade-server ./lemonade-server
COPY --from=builder /app/build/resources ./resources

# Make executables executable
RUN chmod +x ./lemonade-router ./lemonade-server

# Copy custom llama.cpp directly to where lemonade expects it
COPY llamacpp/vulkan /opt/lemonade/llama/vulkan
COPY llamacpp/version.txt /opt/lemonade/llama/vulkan/version.txt

# Create necessary directories
RUN mkdir -p /opt/lemonade/llama/cpu \
    /root/.cache/huggingface

# Expose default port
EXPOSE 8000

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8000/live || exit 1

# Default command: start server in headless mode
ENTRYPOINT ["/opt/lemonade/lemonade-server"]
CMD ["serve", "--no-tray", "--host", "0.0.0.0"]
