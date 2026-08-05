#!/bin/bash
# buildPush.sh — build the LPS2 image locally and deploy it to fly.io.
#
# Built locally rather than on fly's remote builder for the same reason LE2 is:
# the build stamps the image with the git revision it came from, and a remote
# builder would stamp whatever it happened to fetch. `fly deploy --local-only`
# then pushes the image that was actually tested.
#
# Prerequisites: docker, flyctl, and `fly auth login`.
set -e

cd "$(dirname "$0")"

# Logical English, into vendor/le2/, so the image can compile `.le` in its own
# process (docs/le_lps_interface.md §3.5). Skipped, with a note, when there is
# no checkout to vendor from — the image is then simply one without Logical
# English, which is a supported state and not an error.
LE2_DIR="${LPS_LE2_LIB:-${LPS_LE2_DIR:-/LogicalEnglish2}}"
if [ -f "$LE2_DIR/le_service.pl" ]; then
    tools/vendor_le2.sh "$LE2_DIR"
else
    echo "no LE2 checkout at $LE2_DIR: building without Logical English."
    echo "  (set LPS_LE2_DIR, or run tools/vendor_le2.sh /path/to/LogicalEnglish2)"
fi

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

# A deployment with no token is open to anyone who finds it. Since the sandbox
# (docs/deploy.md) that no longer means "open Prolog interpreter" — a program's
# own Prolog is checked before it runs — but it does still mean anybody may keep
# the machine busy, so say which of the two you are choosing.
if ! fly secrets list 2>/dev/null | grep -q LPS_TOKEN; then
    echo
    echo "NOTE: LPS_TOKEN is not set on this app, so anyone who finds it can use it."
    echo "      A program's Prolog is sandboxed before it runs, so this is a question"
    echo "      of whose CPU it is rather than whose machine. Fine for a class demo;"
    echo "      not for a machine you care about:"
    echo "         fly secrets set LPS_TOKEN=\$(openssl rand -hex 24)"
    echo "      With one set, open the IDE once as  https://<app>/ide?token=<it>"
    echo
fi

fly deploy --local-only
