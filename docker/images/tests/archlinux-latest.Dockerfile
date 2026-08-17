FROM archlinux:latest

# Prefer a generated UTF-8 locale for predictable test environments.
ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8

RUN pacman -Syu --noconfirm \
    bash curl sudo libnewt msmtp s-nail bats git python python-pip cronie \
    procps ca-certificates bc \
    && sed -i 's/^#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen \
    && grep -qxF 'en_US.UTF-8 UTF-8' /etc/locale.gen || echo 'en_US.UTF-8 UTF-8' >> /etc/locale.gen \
    && locale-gen \
    && pacman -Scc --noconfirm

RUN python -m pip install --break-system-packages --no-cache-dir lizard || \
    pip install --no-cache-dir lizard

COPY docker/images/tests/scripts/common.sh /tmp/common.sh
ARG CI_UID=1000
ARG CI_GID=1000
ENV CI_UID=${CI_UID} CI_GID=${CI_GID}
RUN bash -c 'source /tmp/common.sh && create_ci_user pi "$CI_UID" "$CI_GID" && prepare_mail_dirs' && rm -f /tmp/common.sh

USER pi
WORKDIR /home/pi
COPY --chown=pi:pi . .
RUN bash -c 'shopt -s nullglob; files=(scripts/*.sh install.sh uninstall.sh tests/*.sh lib/*.sh); \
    ((${#files[@]})) || exit 1; chmod +x "${files[@]}"'

CMD ["./tests/run_suite.sh"]
