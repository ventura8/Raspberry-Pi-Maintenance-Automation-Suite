#!/usr/bin/env bash
# Shared Docker build helpers for CI/local pipelines.
set -euo pipefail

DOCKER_BIN="${DOCKER_BIN:-docker}"

_docker_host_uid_gid() {
    printf '%s %s\n' "$(id -u)" "$(id -g)"
}

image_slug_from_ref() {
    local image="$1"
    image="${image//\//-}"
    image="${image//:/-}"
    printf '%s\n' "$image"
}

dockerfile_for_distro() {
    local image="$1"
    local slug
    slug=$(image_slug_from_ref "$image")
    printf '%s\n' "docker/images/tests/${slug}.Dockerfile"
}

# Image tag includes host UID so bind-mounted checkouts are writable by USER pi.
test_image_tag_for_slug() {
    local slug="$1"
    local uid
    uid="$(id -u)"
    printf 'rpi-maintenance-test:%s-u%s\n' "$slug" "$uid"
}

docker_build_with_cache() {
    local dockerfile="$1"
    local tag="$2"
    local context="${3:-.}"
    local cache_dir="${4:-}"
    local cache_name="${5:-default}"
    local host_uid host_gid
    local -a build_cmd

    host_uid="$(id -u)"
    host_gid="$(id -g)"

    if [ "${SKIP_DOCKER_BUILD:-0}" = "1" ] && "$DOCKER_BIN" image inspect "$tag" > /dev/null 2>&1; then
        echo "Skipping docker build for $tag (SKIP_DOCKER_BUILD=1)"
        return 0
    fi

    mkdir -p "$(dirname "$dockerfile")"

    # Match container USER pi to the host checkout owner when the Dockerfile supports it.
    build_cmd=(
        -f "$dockerfile"
        -t "$tag"
    )
    if grep -q 'CI_UID' "$dockerfile" 2> /dev/null; then
        build_cmd+=(--build-arg "CI_UID=${host_uid}" --build-arg "CI_GID=${host_gid}")
    fi

    if [ -n "$cache_dir" ]; then
        # Cache key includes UID so local (1000) and Actions (often 1001) do not collide.
        mkdir -p "$cache_dir/${cache_name}-u${host_uid}"
        if "$DOCKER_BIN" buildx version > /dev/null 2>&1; then
            "$DOCKER_BIN" buildx build \
                --load \
                --cache-from "type=local,src=$cache_dir/${cache_name}-u${host_uid}" \
                --cache-to "type=local,dest=$cache_dir/${cache_name}-u${host_uid},mode=max" \
                "${build_cmd[@]}" \
                "$context"
            return $?
        fi
    fi
    "$DOCKER_BIN" build "${build_cmd[@]}" "$context"
}
