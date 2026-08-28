#!/usr/bin/env bash
set -Eeuo pipefail

: "${TEST_DATABASE_URL:?TEST_DATABASE_URL must point to a disposable PostgreSQL database}"
PYTHON_IMAGE="${PYTHON_IMAGE:-m.daocloud.io/docker.io/library/python:3.12-slim}"
PYPI_INDEX_URL="${PYPI_INDEX_URL:-https://mirrors.tuna.tsinghua.edu.cn/pypi/web/simple}"

docker run --rm --network host \
  -e TEST_DATABASE_URL="$TEST_DATABASE_URL" \
  -e PYPI_INDEX_URL="$PYPI_INDEX_URL" \
  -v "$(cd "$(dirname "${BASH_SOURCE[0]}")/../backend" && pwd):/src" \
  -w /src \
  "$PYTHON_IMAGE" \
  sh -c 'pip install --disable-pip-version-check -i "$PYPI_INDEX_URL" -e ".[dev]" && python -m pytest tests/e2e/test_two_person_task_approval.py -q -s'
