#!/usr/bin/env bash
set -Eeuo pipefail

: "${TEST_DATABASE_URL:?TEST_DATABASE_URL must point to a disposable PostgreSQL database}"
PYTHON_IMAGE="${PYTHON_IMAGE:-m.daocloud.io/docker.io/library/python:3.12-slim}"
PYPI_INDEX_URL="${PYPI_INDEX_URL:-http://mirrors.aliyun.com/pypi/simple/}"
TEST_DOCKER_NETWORK="${TEST_DOCKER_NETWORK:-host}"

docker run --rm --network "$TEST_DOCKER_NETWORK" \
  -e TEST_DATABASE_URL="$TEST_DATABASE_URL" \
  -e PYPI_INDEX_URL="$PYPI_INDEX_URL" \
  -v "$(cd "$(dirname "${BASH_SOURCE[0]}")/../backend" && pwd):/src" \
  -w /src \
  "$PYTHON_IMAGE" \
  sh -c 'pip install --disable-pip-version-check -i "$PYPI_INDEX_URL" --trusted-host mirrors.aliyun.com -e ".[dev]" && python -m pytest tests/e2e/test_two_person_task_approval.py -q -s'
