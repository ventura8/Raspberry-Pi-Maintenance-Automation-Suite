______________________________________________________________________

## name: distro-matrix-tester description: Build and run Pi-capable distro Docker lanes (compat + e2e) and keep matrix Dockerfiles/CI in sync.

# Distro Matrix Tester Skill

Use when changing Docker test images, matrix scripts, CI `distro-tests`, or `lib/os_pkg.sh` portability.

## Supported lanes

Pi-capable OS families (Pi 3/4 class; Pi 5 support varies upstream):

1. `debian:trixie` — coverage gate + Raspberry Pi OS family
1. `ubuntu:26.04`
1. `fedora:44`
1. `rocky:9`
1. `archlinux:latest`

Dockerfiles: `docker/images/tests/<slug>.Dockerfile`
Orchestration: `scripts/run_docker_matrix.sh`
Local wrapper: `scripts/build-and-test.sh`

## Hard rules

1. Adding/removing a lane updates **matrix script + CI workflow + Dockerfile + docs/AGENTS** together.
1. Compat lane runs maintenance suite + `scripts/run_distro_compat_smoke.sh` (real text install,
   `--update`, and uninstall — failures are fatal).
1. E2E lane uses `REAL_DEPS=1 ./scripts/run_e2e.sh` (real packages; mock HW/destructive only),
   including `tests/e2e/*.bats`, text fresh install, `--update`, and uninstall — failures are fatal.
1. Default matrix / `--full` runs **compat then e2e** in the same container per distro.
1. CI images validate package-manager paths (apt/dnf/pacman), not physical Pi hardware.
1. Keep lint image separate: `docker/images/lint/debian-trixie.Dockerfile`.
1. Shared install/uninstall helpers live in `scripts/matrix_install_flow.sh`.
1. Test images should provide a generated UTF-8 locale (`en_US.UTF-8`) for predictable environments.

## Commands

```bash
# All lanes, parallel (compat+e2e each)
./scripts/run_docker_matrix.sh --parallel

# Single lane
./scripts/run_docker_matrix.sh --distro fedora:44 --serial

# Compat or e2e only
./scripts/run_docker_matrix.sh --compat-only --parallel
./scripts/run_docker_matrix.sh --e2e-only --distro rocky:9 --serial

# Coverage gate only
./scripts/run_docker_matrix.sh --coverage-gate
```

Tee logs:

```bash
mkdir -p reports/distro-logs
./scripts/run_docker_matrix.sh --distro archlinux:latest --serial \
  2>&1 | tee reports/distro-logs/archlinux-latest-manual.log
```

## OS family checks inside images

1. Debian/Ubuntu: `msmtp`/`mailutils`/`whiptail`/`cron` (images may also ship `ssmtp` for legacy fallback coverage)
1. Fedora/Rocky: `newt`/`msmtp`/`cronie` (via `lib/os_pkg.sh` mappings); Rocky images install `curl`
   with `dnf --allowerasing` so `curl-minimal` on the base image does not conflict
1. Arch: `libnewt`/`msmtp`/`cronie`

## Output

Report lanes run, pass/fail, Dockerfile/CI sync status, and any family-specific package gaps.
