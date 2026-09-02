#!/usr/bin/env bash
set -euo pipefail

if (($# != 2)); then
  printf 'usage: %s ARTIFACT FIXTURE\n' "$0" >&2
  exit 2
fi

artifact="$(realpath "$1")"
fixture="$(realpath "$2")"

[[ -f "$artifact" ]] || { printf 'artifact is not a regular file: %s\n' "$artifact" >&2; exit 1; }
[[ -f "$fixture" ]] || { printf 'fixture is not a regular file: %s\n' "$fixture" >&2; exit 1; }

work_root="$(mktemp -d)"
trap 'rm -rf "$work_root"' EXIT
workflow="$work_root/WORKFLOW.md"

sha256() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

cat >"$workflow" <<EOF
---
tracker:
  kind: "sqlite"
  database_path: "$fixture"
  project_slug: "alpha"
  active_states: ["QUEUED"]
  terminal_states: ["READY_FOR_HUMAN_MERGE"]
workspace:
  root: "$work_root/workspaces"
---
Artifact SQLite tracker smoke.
EOF

before="$(sha256 "$fixture")"
version="$("$artifact" --version)"
[[ -n "$version" ]] || { printf 'artifact --version returned empty output\n' >&2; exit 1; }

output="$(cd "$work_root" && "$artifact" --check-tracker "$workflow")"
printf '%s\n' "$output"
grep -F "tracker check passed" <<<"$output" >/dev/null
grep -F "issues=2" <<<"$output" >/dev/null
grep -F $'T-000001\tAlpha queued\tQUEUED' <<<"$output" >/dev/null
if grep -F "Beta" <<<"$output" >/dev/null; then
  printf 'artifact SQLite smoke leaked a non-alpha task\n' >&2
  exit 1
fi

after="$(sha256 "$fixture")"
[[ "$before" == "$after" ]] || { printf 'artifact SQLite smoke changed the fixture\n' >&2; exit 1; }
printf 'artifact SQLite tracker smoke passed (version %s; fixture unchanged)\n' "$version"
