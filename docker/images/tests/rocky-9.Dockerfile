FROM rockylinux:9

# Prefer a generated UTF-8 locale for predictable test environments.
ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8

RUN dnf install -y epel-release-9 \
    && dnf install -y --allowerasing \
    bash-5.1.8 \
    bats-1.8.0 \
    bc-1.07.1 \
    ca-certificates-2025.2.80_v9.0.305 \
    cronie-1.5.7 \
    curl-7.76.1 \
    git-2.52.0 \
    glibc-langpack-en-2.34 \
    msmtp-1.8.25 \
    newt-0.52.21 \
    procps-ng-3.3.17 \
    python3-3.9.25 \
    python3-pip-21.3.1 \
    s-nail-14.9.22 \
    sudo-1.9.17p2 \
    && dnf clean all \
    && python3 -m pip install --no-cache-dir \
        --only-binary :all: 'lizard==1.24.0'

COPY docker/images/tests/scripts/common.sh /tmp/common.sh
ARG CI_UID=1000
ARG CI_GID=1000
ENV CI_UID=${CI_UID} CI_GID=${CI_GID}
RUN bash -c 'source /tmp/common.sh \
    && create_ci_user pi "$CI_UID" "$CI_GID" \
    && prepare_mail_dirs' \
    && rm -f /tmp/common.sh

WORKDIR /home/pi
# Narrow copy instead of a recursive `COPY . .`: only what a standalone run of
# the suite needs, keeping build context and any stray local secrets out of the
# image. Copied as root and left root-owned so the unprivileged test user can
# read and execute but not modify the tree -- the same principle as the
# root-owned install tree invariant. The suite writes to /tmp, and matrix runs
# bind-mount the repo over /home/pi anyway.
COPY install.sh uninstall.sh VERSION ./
COPY lib/ ./lib/
COPY scripts/ ./scripts/
COPY tests/ ./tests/
COPY pi-apps/ ./pi-apps/
RUN bash -c 'shopt -s nullglob; \
    files=(scripts/*.sh install.sh uninstall.sh tests/*.sh lib/*.sh); \
    ((${#files[@]})) || exit 1; \
    chmod +x "${files[@]}"'

# Numeric uid (DL3066): resolvable on the host, and it is the uid
# create_ci_user assigned to pi, so HOME still resolves to /home/pi.
USER ${CI_UID}

CMD ["./tests/run_suite.sh"]
