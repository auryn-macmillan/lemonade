#!/bin/bash
set -e

# Copy the latest llama.cpp files over the bundled version
if [ -d "/lemonade-assets/llamacpp/vulkan" ]; then
    echo "Using custom llama.cpp from /lemonade-assets..."
    cp -r /lemonade-assets/llamacpp/vulkan/* /root/.cache/lemonade/bin/llamacpp/vulkan/
    
    # Update version file
    if [ -f "/lemonade-assets/llamacpp/version.txt" ]; then
        cp /lemonade-assets/llamacpp/version.txt /root/.cache/lemonade/bin/llamacpp/vulkan/version.txt
    fi
fi

# Start the original entrypoint
exec /usr/local/bin/docker-entrypoint.sh "$@"