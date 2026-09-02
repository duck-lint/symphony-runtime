#!/usr/bin/env bash
set -euo pipefail

missing=()
for tool in zig xz make; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    missing+=("$tool")
  fi
done

if ((${#missing[@]} > 0)); then
  printf 'Burrito prerequisite check failed: missing %s\n' "${missing[*]}" >&2
  printf 'Install the repository-pinned Zig through mise and provide host xz and make before retrying.\n' >&2
  exit 1
fi

zig_version="$(zig version)"
if [[ "$zig_version" != "0.15.2" ]]; then
  printf 'Burrito prerequisite check failed: expected Zig 0.15.2, found %s\n' "$zig_version" >&2
  exit 1
fi

printf 'Burrito prerequisites: Zig %s, xz, and make are available.\n' "$zig_version"
