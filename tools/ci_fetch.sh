#!/bin/sh
# Fetch the latest CI results (ci branch) into .work/ci without touching the working tree
cd "$(dirname "$0")/.."
git fetch -q origin ci && rm -rf .work/ci && mkdir -p .work/ci && git archive origin/ci | tar -x -C .work/ci && ls .work/ci
