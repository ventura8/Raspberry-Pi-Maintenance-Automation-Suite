FROM debian:trixie-slim

ARG INSTALL_KCOV=1
ENV DEBIAN_FRONTEND=noninteractive
# Prefer a generated UTF-8 locale for predictable test environments.
ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8

RUN apt-get update && apt-get install -y --no-install-recommends \
    bash curl sudo msmtp ssmtp mailutils whiptail bats git python3 python3-pip cron \
    locales \
    procps cmake make g++ pkg-config libcurl4-openssl-dev libelf-dev libdw-dev \
    binutils-dev libiberty-dev zlib1g-dev bc ca-certificates \
    && sed -i 's/^# *en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen \
    && grep -qxF 'en_US.UTF-8 UTF-8' /etc/locale.gen || echo 'en_US.UTF-8 UTF-8' >> /etc/locale.gen \
    && locale-gen \
    && update-locale LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 \
    && rm -rf /var/lib/apt/lists/*

RUN python3 -m pip install --break-system-packages --no-cache-dir lizard

COPY docker/images/tests/scripts/common.sh /tmp/common.sh
ARG CI_UID=1000
ARG CI_GID=1000
ENV CI_UID=${CI_UID} CI_GID=${CI_GID}
RUN bash -c 'source /tmp/common.sh && create_ci_user pi "$CI_UID" "$CI_GID" && prepare_mail_dirs' \
    && if [ "$INSTALL_KCOV" = "1" ]; then bash -c 'source /tmp/common.sh && install_kcov_from_source v43'; fi \
    && rm -f /tmp/common.sh

USER pi
WORKDIR /home/pi
COPY --chown=pi:pi . .
RUN bash -c 'shopt -s nullglob; files=(scripts/*.sh install.sh uninstall.sh tests/*.sh lib/*.sh); \
    ((${#files[@]})) || exit 1; chmod +x "${files[@]}"'

CMD ["./tests/run_suite.sh"]
