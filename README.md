# symphony-runtime

The parent harness is the canonical SYMPHONY authority. Runtime is the
project-independent deterministic executor; it does not redefine lifecycle
meaning.

Runtime owns:

- reading the Pilot-authorized project execution projection and grant;
- task-scoped PM/Dispatcher reasoning continuity;
- fresh specialist executions;
- App Server, process, session, and workspace mechanics;
- exact capability instantiation and enforcement; and
- execution observation returned to Pilot.

Pilot owns task identity, lifecycle state, eligibility, grants, reconciliation,
repository authority, publication, and the local API/UI projection. Runtime
cannot assign, broaden, or reinterpret capability and cannot write Pilot
lifecycle state.

The canonical topology is a task-scoped persistent PM/Dispatcher followed by
fresh Planner, Reviewer, Implementer, Adversary, and Archivist executions.
There is no Architect actor. The parent harness defines the lifecycle; this
repository documents only Runtime's execution boundary.

## Build boundary

From the Runtime repository's Linux/WSL view, use the reviewed toolchain and
the repository's normal CI target:

    cd elixir
    mise exec -- make ci

The production artifact is built with `mise exec -- make artifact`. Build and
test results are evidence about the current implementation only; they do not
establish conformance with the frozen lifecycle.

## Role and write boundary

Planner may write only bounded plan and decision-memory artifacts.
Implementer may write only its authorized project seam. Archivist may write
only bounded archive, documentation, and project-memory artifacts. Reviewer,
Adversary, and PM/Dispatcher are non-writing.

Runtime instantiates the exact separate grant supplied by Pilot. For every
authorized writer, the host broker observes and validates the exact filesystem
delta against that grant, then stages and commits accepted changes. Roles never
write .git or perform Git staging/commit. There is no shared broad writable
root.

## Evidence status

The supervised-local substrate and Runtime/App Server integration are proven
under explicit operator supervision. The frozen fresh-specialist lifecycle,
writer brokerage, unattended credential isolation, publication, and merge are
not claimed live-proven by that evidence.

Build and test commands describe the current implementation, not conformance
with the frozen lifecycle. Runtime schedules only Pilot-authorized dispatches;
it has no independent lifecycle scheduler or lifecycle authority.
