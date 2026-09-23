FROM debian:trixie-slim

ENV DEBIAN_FRONTEND=noninteractive
ENV LANG=C.UTF-8

RUN apt-get update && apt-get install -y --no-install-recommends \
    bash \
    ca-certificates \
    curl \
    git \
    python3 \
    python3-pip \
    shellcheck \
    shfmt \
    yamllint \
    && rm -rf /var/lib/apt/lists/*

# Pinned hadolint + actionlint (immutable release assets). hadolint is
# verified natively by ADD --checksum; actionlint ships as a tarball, so its
# extracted binary is checked with sha256sum after unpacking.
ARG HADOLINT_VERSION=v2.12.0
ARG ACTIONLINT_VERSION=1.7.7
ARG ACTIONLINT_SHA256=\
9f7dedb4e23f89f2922073d1a6720405b7b520d4f5832ebb96f0d55a2958886c
ADD --checksum=sha256:\
56de6d5e5ec427e17b74fa48d51271c7fc0d61244bf5c90e828aab8362d55010 \
"https://github.com/hadolint/hadolint/releases/download\
/${HADOLINT_VERSION}/hadolint-Linux-x86_64" \
    /usr/local/bin/hadolint
ADD "https://github.com/rhysd/actionlint/releases/download\
/v${ACTIONLINT_VERSION}/actionlint_${ACTIONLINT_VERSION}\
_linux_amd64.tar.gz" \
    /tmp/actionlint.tar.gz
RUN chmod +x /usr/local/bin/hadolint \
    && tar -xzf /tmp/actionlint.tar.gz -C /tmp actionlint \
    && echo "${ACTIONLINT_SHA256}  /tmp/actionlint" | sha256sum -c - \
    && mv /tmp/actionlint /usr/local/bin/actionlint \
    && chmod +x /usr/local/bin/actionlint \
    && rm -f /tmp/actionlint.tar.gz \
    && python3 -m pip install --break-system-packages --no-cache-dir \
        --only-binary :all: \
        'mdformat==1.0.0' 'mdformat-gfm==1.0.0' 'lizard==1.24.0'

WORKDIR /workspace
# Narrow copy: lint-in-docker.sh bind-mounts the repo over /workspace, so
# only the files the chmod step below needs are baked in.
COPY install.sh uninstall.sh ./
COPY lib/ ./lib/
COPY scripts/ ./scripts/
COPY tests/ ./tests/
RUN bash -c 'shopt -s nullglob; \
    files=(tests/*.sh scripts/*.sh scripts/coverage/*.sh \
        install.sh uninstall.sh lib/*.sh); \
    ((${#files[@]})) || exit 1; \
    chmod +x "${files[@]}"'

CMD ["bash", "-lc", "STRICT_MODE=true ./tests/lint.sh"]
