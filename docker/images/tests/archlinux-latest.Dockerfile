FROM archlinux:latest

# Prefer a generated UTF-8 locale for predictable test environments.
ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8

RUN pacman -Syu --noconfirm \
    bash curl sudo libnewt msmtp msmtp-mta s-nail bats git python python-pip cronie \
    procps ca-certificates bc \
    && sed -i 's/^#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen \
    && grep -qxF 'en_US.UTF-8 UTF-8' /etc/locale.gen || echo 'en_US.UTF-8 UTF-8' >> /etc/locale.gen \
    && locale-gen \
    && pacman -Scc --noconfirm

RUN python -m pip install --break-system-packages --no-cache-dir \
        --only-binary :all: 'lizard==1.24.0' \
    || pip install --no-cache-dir --only-binary :all: 'lizard==1.24.0'

COPY docker/images/tests/scripts/common.sh /tmp/common.sh
ARG CI_UID=1000
ARG CI_GID=1000
ENV CI_UID=${CI_UID} CI_GID=${CI_GID}
RUN bash -c 'source /tmp/common.sh && create_ci_user pi "$CI_UID" "$CI_GID" && prepare_mail_dirs' && rm -f /tmp/common.sh

USER pi
WORKDIR /home/pi
# Narrow copy instead of a recursive `COPY . .`: only what a standalone run of
# the suite needs. The matrix bind-mounts the repo over /home/pi anyway, so
# this keeps build context (and any stray local secrets) out of the image.
COPY --chown=pi:pi install.sh uninstall.sh VERSION ./
COPY --chown=pi:pi lib/ ./lib/
COPY --chown=pi:pi scripts/ ./scripts/
COPY --chown=pi:pi tests/ ./tests/
COPY --chown=pi:pi pi-apps/ ./pi-apps/
RUN bash -c 'shopt -s nullglob; files=(scripts/*.sh install.sh uninstall.sh tests/*.sh lib/*.sh); \
    ((${#files[@]})) || exit 1; chmod +x "${files[@]}"'

CMD ["./tests/run_suite.sh"]
