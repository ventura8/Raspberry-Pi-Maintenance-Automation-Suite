FROM archlinux:latest

# Prefer a generated UTF-8 locale for predictable test environments.
ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8

RUN pacman -Syu --noconfirm \
    bash bats bc ca-certificates cronie curl git libnewt msmtp msmtp-mta \
    procps python python-pip s-nail sudo \
    && sed -i 's/^#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen \
    && { grep -qxF 'en_US.UTF-8 UTF-8' /etc/locale.gen \
        || echo 'en_US.UTF-8 UTF-8' >> /etc/locale.gen; } \
    && locale-gen \
    && pacman -Scc --noconfirm \
    && { python -m pip install --break-system-packages --no-cache-dir \
            --only-binary :all: 'lizard==1.24.0' \
        || pip install --no-cache-dir \
            --only-binary :all: 'lizard==1.24.0'; }

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

USER pi

CMD ["./tests/run_suite.sh"]
