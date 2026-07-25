#!/bin/bash
# buildPush.sh — build the LPS(2) image locally and deploy it to fly.io.
#
# Built locally rather than on fly's remote builder for the same reason LE2 is:
# the build stamps the image with the git revision it came from, and a remote
# builder would stamp whatever it happened to fetch. `fly deploy --local-only`
# then pushes the image that was actually tested.
#
# Prerequisites: docker, flyctl, and `fly auth login`.
set -e

cd "$(dirname "$0")"

GIT_HASH=$(git rev-parse --short HEAD)
GIT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
BUILD_DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
BUILD_INFO="${GIT_BRANCH}@${GIT_HASH} (${BUILD_DATE})"

echo "Building lps2 with info: ${BUILD_INFO}"
docker build --build-arg BUILD_INFO="${BUILD_INFO}" -t lps2 .

if [ "${1:-}" = "--build-only" ]; then
    echo "built lps2:latest; skipping deploy"
    exit 0
fi

# A deployment with no token is an open Prolog interpreter. Say so, once,
# rather than discovering it later.
if ! fly secrets list 2>/dev/null | grep -q LPS_TOKEN; then
    echo
    echo "WARNING: LPS_TOKEN is not set on this app. /lpsapi compiles and runs"
    echo "         arbitrary Prolog, so an untokened deployment is public."
    echo "         fly secrets set LPS_TOKEN=\$(openssl rand -hex 24)"
    echo
fi

fly deploy --local-only
