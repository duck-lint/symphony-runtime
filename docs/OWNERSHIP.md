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

The exact OpenAI Symphony source commit for the imported tree is **not
mechanically identifiable from this repository**.

The strongest local evidence is:

- `b8cac304f86ba18a02a20ac5b2d94da0f2672799` is the repository's initial,
  parentless commit and adds the complete runtime tree in one local import;
- that commit contains no upstream SHA, source remote, import manifest, or
  subtree history;
- the only configured Git remote is the project-owned
  `https://github.com/duck-lint/symphony-runtime.git`; and
- the repository retains `LICENSE` and `NOTICE`, but those files do not name
  an exact source commit.

Accordingly, `b8cac304f86ba18a02a20ac5b2d94da0f2672799` is recorded here as the
local import boundary, **not** misrepresented as the upstream commit. No
stronger commit attribution is licensed by the repository evidence.

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
SYMPHONY_BIN=/absolute/path/to/symphony-runtime/elixir/bin/symphony \
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
