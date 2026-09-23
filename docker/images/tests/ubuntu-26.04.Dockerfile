FROM ubuntu:26.04

ENV DEBIAN_FRONTEND=noninteractive
# Prefer a generated UTF-8 locale for predictable test environments.
ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8

RUN apt-get update && apt-get install -y --no-install-recommends \
    'bash=5.3*' \
    'bats=1.13.0*' \
    'bc=1.07.1*' \
    'ca-certificates=20260601~26.04.1*' \
    'cron=3.0pl1*' \
    'curl=8.18.0*' \
    'git=1:2.53.0*' \
    'locales=2.43*' \
    'mailutils=1:3.20*' \
    'msmtp=1.8.32*' \
    'procps=2:4.0.4*' \
    'python3-pip=25.1.1+dfsg*' \
    'python3=3.14.3*' \
    'ssmtp=2.65*' \
    'sudo=1.9.17p2*' \
    'whiptail=0.52.25*' \
    && sed -i 's/^# *en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen \
    && { grep -qxF 'en_US.UTF-8 UTF-8' /etc/locale.gen \
        || echo 'en_US.UTF-8 UTF-8' >> /etc/locale.gen; } \
    && locale-gen \
    && update-locale LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 \
    && rm -rf /var/lib/apt/lists/* \
    && { python3 -m pip install --break-system-packages --no-cache-dir \
            --only-binary :all: 'lizard==1.24.0' \
        || python3 -m pip install --no-cache-dir \
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

# Numeric uid (DL3066): resolvable on the host, and it is the uid
# create_ci_user assigned to pi, so HOME still resolves to /home/pi.
USER ${CI_UID}

CMD ["./tests/run_suite.sh"]
