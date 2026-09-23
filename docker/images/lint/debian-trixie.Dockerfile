FROM debian:trixie-slim

ENV DEBIAN_FRONTEND=noninteractive
ENV LANG=C.UTF-8

RUN apt-get update && apt-get install -y --no-install-recommends \
    'bash=5.2.37*' \
    'ca-certificates=20250419*' \
    'curl=8.14.1*' \
    'git=1:2.47.3*' \
    'python3-pip=25.1.1+dfsg*' \
    'python3=3.13.5*' \
    'shellcheck=0.10.0*' \
    'shfmt=3.8.0*' \
    'yamllint=1.37.1*' \
    && rm -rf /var/lib/apt/lists/*

# Pinned hadolint + actionlint, both verified natively by ADD --checksum
# against the publishers' own release checksums.
ARG HADOLINT_VERSION=v2.15.1
ARG ACTIONLINT_VERSION=1.7.12
ADD --checksum=sha256:\
c7187db94eeeeca956519a6af171adc31453941a1e777961f6e680f697c8c507 \
"https://github.com/hadolint/hadolint/releases/download\
/${HADOLINT_VERSION}/hadolint-linux-x86_64" \
    /usr/local/bin/hadolint
ADD --checksum=sha256:\
8aca8db96f1b94770f1b0d72b6dddcb1ebb8123cb3712530b08cc387b349a3d8 \
"https://github.com/rhysd/actionlint/releases/download\
/v${ACTIONLINT_VERSION}/actionlint_${ACTIONLINT_VERSION}\
_linux_amd64.tar.gz" \
    /tmp/actionlint.tar.gz
RUN chmod +x /usr/local/bin/hadolint \
    && tar -xzf /tmp/actionlint.tar.gz -C /usr/local/bin actionlint \
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
