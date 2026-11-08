#!/bin/sh
# Build GossipCore + coretest in Docker (swift:6.2-noble) and run coretest with the given arguments.
# The build cache lives in the docker volume "gossipbuild".
cd "$(dirname "$0")/.."
MSYS_NO_PATHCONV=1 docker run --rm -v "$(pwd -W 2>/dev/null || pwd):/w" -v gossipbuild:/tmp/b -w /w swift:6.2-noble bash -c "swift build -c release --scratch-path /tmp/b 2>&1 | grep -E 'error' -A3 | head -60; /tmp/b/release/coretest $*"
