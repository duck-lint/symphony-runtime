# SQLite tracker adapter

## Current accepted contract

This adapter is live in the supervised-local MVP. It consumes the current
Pilot schema v2, reads SQLite project-scoped and read-only, and participated in
the live canary traversal. Pilot remains the sole migration, lifecycle, and
reconciliation authority.

Step 3 adds `tracker.kind: sqlite` as a read-only runtime adapter. The
host-owned `symphony-pilot` process remains the sole writer and migration
authority for `control.sqlite3`.

```yaml
tracker:
  kind: sqlite
  database_path: /home/operator/.local/state/symphony-pilot/control.sqlite3
  project_slug: alpha
```

The database path must be an existing absolute regular file. The adapter opens
it with Exqlite's `[:readonly]` mode, enables `query_only`, installs a SQLite
authorizer that rejects mutation/attachment actions, and never executes
`journal_mode` or any migration. Each tracker read opens and closes its own
read-only connection, so committed WAL state is read through SQLite rather
than copied into a potentially stale file.

The adapter supports pilot schema version `2` and the exact migration lineage
`[1, "control-plane-v1"]`, `[2, "control-plane-v2-storage-reservations"]`.
It validates those values and the required columns it
queries. A missing, newer, partial, incompatible, or unreadable database is an
error; it is never represented as an empty task list.

The adapter routing rule is:

```text
dispatchable = no open blockers for the task
```

The orchestrator applies the independent scheduling rule:

```text
scheduler-eligible = tasks.state ∈ configured tracker.active_states
```

Both gates must pass before a task is dispatched. This lets Pilot advance a
task through its lifecycle without teaching Runtime a second lifecycle
vocabulary. `HUMAN_BLOCKED`, `INFRASTRUCTURE_BLOCKED`, and
`READY_FOR_HUMAN_MERGE` remain non-dispatchable unless explicitly requested
and unblocked; the managed Step-6 workflow does not request them. `project`
blockers are read through the same open-blocker predicate and remain a
distinct pilot-side kind; the adapter does not manufacture `blocked_by`
dependency semantics. `active_states` defaults to `QUEUED` for a bare SQLite
configuration, while Step-6 workflow generation explicitly requests its
active lifecycle states. An empty requested state list returns no tasks, not
all tasks.

Rows are scoped by `project_slug` for both state and UUID reads. Local task
UUIDs are the normalized `Issue.id`; labels, native references, URLs,
assignees, priorities, and provider credentials are empty or `nil`. The
adapter advertises no agent tools and no secret environment names.

The checked-in fixture
`test/fixtures/pilot_control_plane_v2.sqlite3` represents the current Pilot v2
contract. Runtime tests consume the fixture only; they do not depend on a
sibling checkout or duplicate the Pilot schema. The accepted live pair is
Pilot `a88b075fb0ab60af369b377992c98706affd3b5e` and Runtime
`bca0d7027c49ef9bc62ee07de0bf669b8d3cb3d6`.

Exqlite is the narrow direct dependency because its low-level SQLite API
supports readonly open mode, prepared statements, bound parameters, row reads,
busy timeouts, and authorizer enforcement without introducing an ORM, Ecto
repository, shell command, or second migration system.

The Runtime production route is SQLite-only. Pilot remains the host-side
configuration and lifecycle authority, while this adapter remains read-only;
Runtime has no GitHub tracker or publication credential path. Supervised-local
Codex integration is proven, but unattended credential isolation and stronger
execution hardening remain outside this adapter's contract.

## Native build and artifact boundary

The physical checkout is used from both Windows and WSL. `mix.exs` therefore
selects an OS-specific build root outside the checkout for every Mix
invocation, so direct commands cannot cross-contaminate native NIF outputs.
Make delegates to that same Mix-level decision. The canonical Linux command is:

```sh
/home/duck-lint/.local/bin/mise exec -- make ci
```

Production packaging uses the existing Burrito release configuration rather
than the development escript. Run `mise exec -- make artifact` on Linux;
`burrito_out/symphony_linux_x86_64` is a self-contained executable containing
the BEAM runtime, application, and platform-specific Exqlite NIF. Its
`--check-tracker WORKFLOW.md` command is a bounded artifact-level proof of
schema validation and one project-scoped read; it does not start the scheduler
or grant the model any database capability. The artifact target stages this
same file at `bin/symphony`, preserving the existing runtime path for the
version/SHA identity pin. Source `mix build` writes only `bin/symphony-dev`; it
does not carry the native release runtime and cannot overwrite the production
path. `scripts/check_artifact_prereqs.sh` checks the pinned Zig tool plus host
`xz` and `make` before a Burrito build begins. The artifact smoke script runs
the built executable against the checked-in pilot-produced fixture and is used
by both the release smoke and the Linux source-validation workflow.
