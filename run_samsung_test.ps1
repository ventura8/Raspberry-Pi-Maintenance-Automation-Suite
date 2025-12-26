#!/usr/bin/env pwsh
# Wrapper to run just Samsung tests
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
docker build -t rpi-maintenance-test -f Dockerfile.test .
docker run --rm rpi-maintenance-test bats tests/component_tests_samsung.bats
