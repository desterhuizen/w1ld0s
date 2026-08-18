# The canonical environment for tests/check.sh.
#
# Same base image as the Tier 2 smoke job, so "it passed locally" and "it
# passed in CI" mean the same thing. tests/check.sh targets Linux + bash 5 +
# GNU userland deliberately; this is how it gets run from a macOS checkout.
FROM ubuntu:26.04

RUN apt-get update -qq && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        bash git shellcheck zsh python3 ca-certificates && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /repo
ENTRYPOINT ["./tests/check.sh"]
