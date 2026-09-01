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
mise exec -- mix setup
mise exec -- mix build
mise exec -- mix test
mise exec -- mix format --check-formatted
mise exec -- mix lint
```

The repository's aggregate CI-equivalent command is:

```sh
mise exec -- make all
```

`mix build` produces `elixir/bin/symphony`. The pilot treats that executable
as host runtime input and pins its reported version and SHA-256 digest before
launch; the executable itself is not copied into a generated project
deployment.

See [docs/OWNERSHIP.md](docs/OWNERSHIP.md) for the bounded provenance and
pilot-integration evidence recorded during the ownership cutover.
