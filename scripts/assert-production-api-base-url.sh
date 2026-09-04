#!/usr/bin/env bash
set -Eeuo pipefail

api_base_url="${1-}"

if [[ ! "$api_base_url" =~ ^https?://[^[:space:]]+$ ]]; then
  printf 'Production Android builds require a valid API_BASE_URL.\n' >&2
  exit 2
fi

if [[ "$api_base_url" =~ ^https?://(localhost|127[.]0[.]0[.]1|0[.]0[.]0[.]0|\[::1\])([/:?]|$) ]]; then
  printf 'Production Android builds must not use a local API_BASE_URL: %s\n' "$api_base_url" >&2
  exit 2
fi
