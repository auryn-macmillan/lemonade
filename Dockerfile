# ==============================================================
# # 1. Build llama.cpp from source with Vulkan support
# # ============================================================
FROM ubuntu:24.04 AS llamacpp-builder

ENV DEBIAN_FRONTEND=noninteractive

ARG LLAMACPP_VERSION=b8766

RUN apt-get update && apt-get install -y \
    build-essential \
    cmake \
    ninja-build \
    git \
    libvulkan-dev \
    glslc \
    && rm -rf /var/lib/apt/lists/*

RUN git clone --depth 1 --branch ${LLAMACPP_VERSION} \
    https://github.com/ggml-org/llama.cpp.git /llama.cpp

WORKDIR /llama.cpp

RUN cmake -B build -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DGGML_VULKAN=ON \
    -DGGML_NATIVE=OFF \
    -DGGML_BACKEND_DL=ON \
    -DGGML_CPU_ALL_VARIANTS=ON \
    -DLLAMA_BUILD_TESTS=OFF \
    -DLLAMA_BUILD_EXAMPLES=ON \
    -DLLAMA_BUILD_SERVER=ON \
    && cmake --build build --config Release -j$(nproc)

# Collect all needed files into a clean output directory
RUN mkdir -p /llamacpp-out && \
    cp build/bin/llama-server /llamacpp-out/ && \
    cp build/bin/llama-cli /llamacpp-out/ && \
    cp build/bin/llama-bench /llamacpp-out/ 2>/dev/null || true && \
    cp build/bin/llama-quantize /llamacpp-out/ 2>/dev/null || true && \
    cp build/bin/llama-gguf-split /llamacpp-out/ 2>/dev/null || true && \
    # Copy all shared libraries
    find build -name "libggml*.so*" -exec cp -a {} /llamacpp-out/ \; && \
    find build -name "libllama*.so*" -exec cp -a {} /llamacpp-out/ \; && \
    find build -name "libmtmd*.so*" -exec cp -a {} /llamacpp-out/ \; && \
    echo "${LLAMACPP_VERSION}" > /llamacpp-out/version.txt

# ==============================================================
# # 2. Build stage — compile lemonade C++ binaries
# # ============================================================
FROM ubuntu:24.04 AS builder

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    build-essential \
    cmake \
    ninja-build \
    libssl-dev \
    pkg-config \
    libdrm-dev \
    git \
    && rm -rf /var/lib/apt/lists/*

COPY . /app
WORKDIR /app

RUN rm -rf build && \
    cmake --preset default && \
    cmake --build --preset default

# Debug: Check build outputs
RUN echo "=== Build directory contents ===" && \
    ls -la build/ && \
    echo "=== Checking for resources ===" && \
    find build/ -name "*.json" -o -name "resources" -type d

# # ============================================================
# # 3. Runtime stage — small, clean image
# # ============================================================
FROM ubuntu:24.04

RUN apt-get update && apt-get install -y \
    libcurl4 \
    curl \
    libssl3 \
    zlib1g \
    libdrm2 \
    vulkan-tools \
    libvulkan1 \
    unzip \
    libgomp1 \
    libatomic1 \
    jq \
    && rm -rf /var/lib/apt/lists/*

# Create application directory
WORKDIR /opt/lemonade

# Copy built executables and resources from builder
COPY --from=builder /app/build/lemond ./lemond
COPY --from=builder /app/build/lemonade-server ./lemonade-server
COPY --from=builder /app/build/lemonade ./lemonade
COPY --from=builder /app/build/resources ./resources

# Make executables executable
RUN chmod +x ./lemond ./lemonade-server ./lemonade

# Copy pre-built llama.cpp vulkan binaries
COPY --from=llamacpp-builder /llamacpp-out/ /opt/lemonade/llama/vulkan/
RUN chmod +x /opt/lemonade/llama/vulkan/llama-server \
    /opt/lemonade/llama/vulkan/llama-cli 2>/dev/null || true

# Create necessary directories
RUN mkdir -p /opt/lemonade/llama/cpu \
    /root/.cache/huggingface \
    /root/.cache/lemonade/bin/llamacpp/vulkan

# Copy entrypoint script
COPY docker-entrypoint.sh /opt/lemonade/docker-entrypoint.sh
RUN chmod +x /opt/lemonade/docker-entrypoint.sh

# Expose default port
EXPOSE 8000

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:8000/live || exit 1

ENTRYPOINT ["/opt/lemonade/docker-entrypoint.sh"]
CMD ["./lemonade-server", "serve", "--no-tray", "--host", "0.0.0.0"]
