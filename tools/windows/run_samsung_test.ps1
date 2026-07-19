#!/usr/bin/env pwsh
# Wrapper to run just Samsung tests
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = (Resolve-Path (Join-Path $scriptDir "..\..")).Path
$dockerfilePath = Join-Path $projectRoot "docker/Dockerfile.test"
docker build -t rpi-maintenance-test -f "$dockerfilePath" "$projectRoot"
docker run --rm rpi-maintenance-test bats tests/component_tests_samsung.bats
