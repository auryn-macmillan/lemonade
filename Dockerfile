# ==============================================================
# # 1. Download pre-built llama.cpp Vulkan release
# # ==============================================================
FROM ubuntu:24.04 AS llamacpp-builder

ENV DEBIAN_FRONTEND=noninteractive

ARG LLAMACPP_VERSION=b9253

RUN apt-get update && apt-get install -y curl unzip && rm -rf /var/lib/apt/lists/*

# Download pre-built Vulkan release from upstream llama.cpp
RUN curl -L -o /tmp/llamacpp-vulkan.tar.gz \
    "https://github.com/ggml-org/llama.cpp/releases/download/${LLAMACPP_VERSION}/llama-${LLAMACPP_VERSION}-bin-ubuntu-vulkan-x64.tar.gz" \
    && mkdir -p /llamacpp-out \
    && tar -xzf /tmp/llamacpp-vulkan.tar.gz --strip-components=1 -C /llamacpp-out/ \
    && rm /tmp/llamacpp-vulkan.tar.gz \
    && echo "${LLAMACPP_VERSION}" > /llamacpp-out/version.txt \
    && chmod +x /llamacpp-out/*

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

# Provide a private runtime directory so lemond can use get_runtime_dir()
RUN mkdir -p /run/lemonade && chmod 700 /run/lemonade
ENV XDG_RUNTIME_DIR=/run/lemonade

# Copy built executables and resources from builder
COPY --from=builder /app/build/lemond ./lemond
COPY --from=builder /app/build/lemonade ./lemonade
COPY --from=builder /app/build/resources ./resources

# Download and install FLM using version from backend_versions.json
RUN FLM_VERSION=$(jq -r '.flm.npu' ./resources/backend_versions.json) && \
    FLM_VERSION_NUM=$(echo $FLM_VERSION | sed 's/^v//') && \
    curl -L -o fastflowlm.deb "https://github.com/FastFlowLM/FastFlowLM/releases/download/${FLM_VERSION}/fastflowlm_${FLM_VERSION_NUM}_ubuntu24.04_amd64.deb" && \
    apt-get update && apt-get install -y libxrt2 libxrt-npu2 && \
    apt-get install -y ./fastflowlm.deb && \
    rm fastflowlm.deb

# Make executables executable
RUN chmod +x ./lemond ./lemonade-server ./lemonade

# Copy pre-built llama.cpp vulkan binaries (built from source for TurboQuant + MTP support)
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

# Use custom entrypoint for llamacpp args and model configs
ENTRYPOINT ["/opt/lemonade/docker-entrypoint.sh"]
CMD ["./lemonade-server", "serve", "--no-tray", "--host", "0.0.0.0"]
