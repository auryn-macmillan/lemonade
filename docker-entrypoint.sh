#!/bin/bash
set -e

BUNDLED_LLAMA_DIR="/opt/lemonade/llama/vulkan"
CACHE_LLAMA_DIR="/root/.cache/lemonade/bin/llamacpp/vulkan"

# Ensure cache directory exists
mkdir -p "$CACHE_LLAMA_DIR"

# Check if we need to update the cached llama.cpp binaries
BUNDLED_VERSION=""
CACHED_VERSION=""

if [ -f "$BUNDLED_LLAMA_DIR/version.txt" ]; then
    BUNDLED_VERSION=$(cat "$BUNDLED_LLAMA_DIR/version.txt" | tr -d '[:space:]')
fi

if [ -f "$CACHE_LLAMA_DIR/version.txt" ]; then
    CACHED_VERSION=$(cat "$CACHE_LLAMA_DIR/version.txt" | tr -d '[:space:]')
fi

if [ -n "$BUNDLED_VERSION" ] && [ "$BUNDLED_VERSION" != "$CACHED_VERSION" ]; then
    echo "[entrypoint] Updating llama.cpp binaries: ${CACHED_VERSION:-none} -> ${BUNDLED_VERSION}"
    # Clean old binaries to avoid stale .so files
    rm -rf "$CACHE_LLAMA_DIR"/*
    cp -a "$BUNDLED_LLAMA_DIR"/* "$CACHE_LLAMA_DIR"/
    echo "[entrypoint] llama.cpp ${BUNDLED_VERSION} installed"
elif [ -n "$BUNDLED_VERSION" ]; then
    echo "[entrypoint] llama.cpp ${BUNDLED_VERSION} already installed"
fi

# Ensure llama-server can find its shared libraries when spawned by lemonade
export LD_LIBRARY_PATH="$CACHE_LLAMA_DIR:${LD_LIBRARY_PATH:-}"

# Execute the main command
exec "$@"
