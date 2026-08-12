______________________________________________________________________

## applyTo: "\*\*/Dockerfile\*" description: "Dockerfile rules for lint and distro test images."

# Dockerfile Instructions

1. Line length ≤ 140; pass `hadolint` without inline ignores.
1. Test images under `docker/images/tests/` must install suite deps for that OS family
   (bash, curl, sudo, bats, mail transport, whiptail/newt/libnewt, python).
1. Reuse `docker/images/tests/scripts/common.sh` helpers (`create_ci_user`, `prepare_mail_dirs`).
1. Keep `debian:trixie` capable of coverage/kcov when used as the coverage gate.
1. Non-root `USER pi` for running tests; passwordless sudo for package/e2e paths.
1. Adding a distro image requires matrix script + CI workflow + docs/AGENTS updates.
