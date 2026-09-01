# Runtime ownership and Step 1 baseline

## Authority

`symphony-runtime` is the owned implementation of the Symphony scheduler and
runner used by `symphony-pilot`. Its checked-in source, tests, and accepted
local changes are the implementation authority for this runtime.

OpenAI Symphony remains historical/reference material. This project does not
promise upstream compatibility, does not treat upstream changes as lifecycle
or architectural authority, and does not need an upstream-sync workflow.
Those statements concern authority and compatibility; they do not erase the
historical Apache licensing and attribution retained in `LICENSE` and
`NOTICE`.

## Historical provenance finding

The imported implementation is mechanically attributable to OpenAI Symphony
commit `8001b52e3062495a16e520e4ceaf8f9de868c4d0`.

The systematic comparison used the parentless local import commit
`b8cac304f86ba18a02a20ac5b2d94da0f2672799` and the upstream commit's Git tree.
It found:

- 117 of 119 local-import files are byte-identical to the upstream blobs,
  including the complete `elixir/lib/` source tree, `mix.exs`, `mix.lock`, and
  tests;
- `.codex/skills/land/land_watch.py` is identical in bytes and differs only in
  file mode (`100644` locally versus `100755` upstream);
- `NOTICE` is the only same-path content mismatch. It is a local
  project/legal packaging file, not a runtime source mismatch;
- no local-import path is extra relative to that upstream tree; and
- 11 upstream paths were intentionally/selectively omitted by the local
  import: `.codex/worktree_init.sh`, the three `.github/media` assets,
  `docs/symphony-smoke-board-review.md`, `docs/symphony-smoke-test-one.md`,
  `elixir/AGENTS.md`, `elixir/README.md`, `elixir/WORKFLOW.md`, `README.md`,
  and `SPEC.md`.

The result is therefore a selective import based on
`8001b52e3062495a16e520e4ceaf8f9de868c4d0`, not a mixed or incompatible
source revision. The local import boundary remains recorded because it is
useful evidence of how this repository was created; it is not substituted for
the historical upstream source baseline.

The omitted `elixir/WORKFLOW.md` was added in this correction round as the
smallest local workflow fixture that satisfies the checked-in runtime tests.
It is not claimed to be byte-identical upstream content; its original absence
remains part of the selective-import comparison. Its tracker-shaped contents
are a test/build fixture at this stage; later local-tracker cutover work remains
deferred.

## Pilot identity integration

The pilot resolves the runtime executable from the explicit `SYMPHONY_BIN`
path or from `PATH`, then compares the executable's reported version and
SHA-256 digest against the host-owned runtime lock. `scripts/pin_runtime.py`
creates that lock; `scripts/project.py` verifies it before containment,
credential acquisition, or process launch. The generated deployment manifest
continues to bind the pilot-owned deployment snapshot to its exact source
contract.

The Step 1 runtime probe is therefore deliberately narrow:

```sh
export SYMPHONY_BIN=/absolute/path/to/symphony-runtime/elixir/bin/symphony
python3 /path/to/symphony-pilot/scripts/pin_runtime.py \
  --project <registered-slug> --symphony "$SYMPHONY_BIN"
```

The runtime now exposes `symphony --version`, so the pilot can mechanically
identify the executable produced by this repository and pin its version and
digest. The pilot still verifies the exact locked executable at startup; no
operator fallback, ambient credential path, or weakened process identity was
introduced. The containment and App Server authentication gates remain
unchanged and are outside Step 1.

This is executable identity evidence, not a claim that a digest alone proves
source provenance. The source-to-artifact relation remains the reviewed WSL
build command and the explicit `SYMPHONY_BIN` path supplied to pinning.

## Deferred seams

SQLite task tracking, GitHub tracker removal, local browser control, task
identity changes, and the Codex App Server credential boundary are later
handoff steps. They are intentionally not implemented by this baseline.
