#!/usr/bin/env bash
set -Eeuo pipefail

# Runtime/build files are the boundary. The Android source test intentionally
# contains forbidden symbol names as assertions, so it is excluded here.
scan_paths=(.github Makefile deploy scripts client/lib client/test client/integration_test client/README.md docs/operations)
existing_paths=()
for path in "${scan_paths[@]}"; do
  [[ -e "$path" ]] && existing_paths+=("$path")
done

if ((${#existing_paths[@]} > 0)) && rg -n --hidden \
  --glob '!scripts/assert-client-boundary.sh' \
  --glob '!client/test/android_entrypoint_test.dart' \
  --glob '!**/__pycache__/**' \
  --glob '!**/.dart_tool/**' \
  --glob '!**/build/**' \
  'flutter build web|Flutter Web static bundle|client/build/web|web_session_flow_test\.dart|kIsWeb|AppPlatform\.web|dart\.library\.js_interop|BrowserClient' \
  "${existing_paths[@]}"; then
  echo "forbidden Android/Web boundary reference remains" >&2
  exit 1
fi

if [[ -e client/web || -e client/build/web ]]; then
  echo "Flutter Web entrypoint/output remains" >&2
  exit 1
fi

test -f web/package.json
test -f web/vite.config.ts
echo "client boundary check passed"
