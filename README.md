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
dependencies, runs `mix hex.audit`, builds the checked-in escript for source
checks, then runs formatting, lint, coverage, and Dialyzer checks.

The Makefile exports an OS-separated `MIX_BUILD_ROOT` outside the checkout:
`$HOME/.local/state/symphony-runtime/mix/linux/_build` on WSL/Linux and the
corresponding user-local Windows path on Windows. The physical F: checkout is
therefore not a shared native build cache.

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

For the source-level checks individually, use the corresponding Make targets:

```sh
mise exec -- make fmt-check
mise exec -- make lint
mise exec -- make coverage
mise exec -- make dialyzer
```

The artifact target also stages that exact Burrito executable at the ignored
`bin/symphony` path, preserving the Step 1 path/version/SHA pinning seam. A
plain `mix build` overwrites that path with the non-production escript, so it is
not a deployment build. Pilot treats the selected executable as host runtime
input and pins its reported version and SHA-256 digest before launch; the
executable itself is not copied into a generated project deployment.

See [docs/OWNERSHIP.md](docs/OWNERSHIP.md) for the bounded provenance and
pilot-integration evidence recorded during the ownership cutover.
