# symphony-runtime

This repository contains the Symphony implementation that `symphony-pilot`
builds, identifies, pins, and runs for the local control plane. The runtime
source here is owned by this project.

OpenAI Symphony is historical provenance and reference material only. Upstream
compatibility is not a requirement, upstream changes are not lifecycle or
architectural authority, and this project does not require an upstream-sync
workflow. The Apache `LICENSE` and `NOTICE` are retained for attribution and
licensing.

## Build and test on WSL

Physical runtime work is performed from the WSL/Linux environment. From the
WSL view of this checkout:

```sh
cd /mnt/f/PROJECT-REPOS/symphony-runtime/elixir
mise trust
mise install
mise exec -- make ci
```

This is the canonical WSL build/test procedure. `make ci` installs
dependencies, runs `mix hex.audit`, builds the development escript for source
checks, then runs formatting, lint, coverage, and Dialyzer checks.

`mix.exs` selects an OS-separated build root for every Mix invocation, including
direct `mix` commands and Make children. Linux uses
`$HOME/.local/state/symphony-runtime/mix/linux/_build`; Windows uses the
corresponding `%LOCALAPPDATA%` path. The physical F: checkout's `_build` is not
consulted for project dependencies or native output. `MIX_BUILD_ROOT` remains an
explicit override for an isolated test.

To inspect the resolved path directly on either supported host, run from this
directory:

```sh
mix run --no-compile -e 'IO.puts(Mix.Project.build_path())'
```

The result must be under the Windows `.../symphony-runtime/mix/windows/_build`
root or the Linux `.../symphony-runtime/mix/linux/_build` root. `make build`
and `make test` invoke the same project-level configuration; they must not
reintroduce the checkout `_build`.

The self-contained production artifact is written to:

```text
elixir/burrito_out/symphony_linux_x86_64
```

Build it with `mise exec -- make artifact`. It includes the runtime and native
Exqlite NIF and can be copied as a single deployment file. `--version` reports
the application version without starting the service. `--check-tracker
<WORKFLOW.md>` is an offline artifact smoke command: it validates the
configured pilot schema and performs one project-scoped SQLite read without
requiring the acknowledgement flag or starting the service.

The repository pins Zig `0.15.2` in `mise.toml`. Burrito also requires host
`xz` and `make`; `make artifact` performs an early version/tool presence check
and fails before the release build if either is absent.

For the source-level checks individually, use the corresponding Make targets:

```sh
mise exec -- make fmt-check
mise exec -- make lint
mise exec -- make coverage
mise exec -- make dialyzer
```

The artifact target stages the production Burrito executable at the ignored
`bin/symphony` path. That path has one meaning: the deployable runtime used by
Pilot's Step 1 path/version/SHA pinning seam. A plain `mix build` stages its
development escript at `bin/symphony-dev` and cannot replace the production
path. Pilot treats the selected executable as host runtime input and pins its
reported version and SHA-256 digest before launch; the executable itself is not
copied into a generated project deployment.

For a local production proof after `make artifact`, run:

```sh
bash scripts/smoke_burrito_sqlite.sh bin/symphony test/fixtures/pilot_control_plane_v1.sqlite3
```

See [docs/OWNERSHIP.md](docs/OWNERSHIP.md) for the bounded provenance and
pilot-integration evidence recorded during the ownership cutover.
