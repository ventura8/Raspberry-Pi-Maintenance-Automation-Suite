FROM fedora:44

# Non-C LANG is required so GNU gettext honors LANGUAGE (C/C.UTF-8 ignores it).
ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8

RUN dnf install -y \
    bash curl sudo newt msmtp s-nail bats git python3 python3-pip cronie \
    gettext glibc-langpack-en \
    procps ca-certificates bc \
    && dnf clean all

RUN python3 -m pip install --no-cache-dir lizard

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
