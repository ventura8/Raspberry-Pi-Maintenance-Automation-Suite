FROM rockylinux:9

# Prefer a generated UTF-8 locale for predictable test environments.
ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8

RUN dnf install -y epel-release \
    && dnf install -y --allowerasing \
    bash curl sudo newt msmtp s-nail bats git python3 python3-pip cronie \
    glibc-langpack-en \
    procps ca-certificates bc \
    && dnf clean all

RUN python3 -m pip install --no-cache-dir --only-binary :all: 'lizard==1.24.0'

COPY docker/images/tests/scripts/common.sh /tmp/common.sh
ARG CI_UID=1000
ARG CI_GID=1000
ENV CI_UID=${CI_UID} CI_GID=${CI_GID}
RUN bash -c 'source /tmp/common.sh && create_ci_user pi "$CI_UID" "$CI_GID" && prepare_mail_dirs' && rm -f /tmp/common.sh

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
RUN bash -c 'shopt -s nullglob; files=(scripts/*.sh install.sh uninstall.sh tests/*.sh lib/*.sh); \
    ((${#files[@]})) || exit 1; chmod +x "${files[@]}"'

USER pi

CMD ["./tests/run_suite.sh"]
