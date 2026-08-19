#!/usr/bin/env bash
# Run tests/check.sh inside the container it is written for.
#
# tests/check.sh needs bash 5 and GNU userland, which macOS does not have.
# This wrapper is the supported way to run the checks from a Mac checkout.
# Docker caches the image layers, so only the first run pays the build cost.
#
#   ./tests/check-docker.sh            # same flags as tests/check.sh
#   ./tests/check-docker.sh -v --strict
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

docker build -q -t w1ld0s-checks "$ROOT/tests" >/dev/null
# Read-only mount: the checks must never mutate the working tree. git needs the
# directory marked safe because the bind-mounted files are owned by the host uid.
exec docker run --rm \
  -v "$ROOT:/repo:ro" \
  -e GIT_CONFIG_COUNT=1 \
  -e GIT_CONFIG_KEY_0=safe.directory \
  -e GIT_CONFIG_VALUE_0=/repo \
  w1ld0s-checks "$@"
