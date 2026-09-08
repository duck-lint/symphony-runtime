# Runtime ownership

The parent harness is authoritative for the product thesis, lifecycle, and
cross-repository contracts. Runtime owns deterministic execution only.

## Runtime owns

- consuming the current read-only Pilot execution projection and grant;
- maintaining task-scoped PM/Dispatcher reasoning continuity;
- launching fresh specialist executions;
- App Server, process, session, workspace, and containment mechanics;
- enforcing exactly the capability Pilot authorized; and
- returning host-observed execution evidence.

Pilot owns lifecycle meaning, eligibility, accepted transitions, blockers,
termination classification, repository authority, grants, reconciliation,
publication, and the local API/UI projection. Runtime must not create a
second lifecycle model or scheduler authority.

The task-scoped PM/Dispatcher is persistent in the canonical model across
specialist results and working rounds, including human-authorized later
lifecycles for the same task. The harness does not prescribe crash/restart
mechanics or require one immortal process, session, or thread. Every
specialist execution remains fresh.

## Capability boundary

Planner, Implementer, and Archivist receive separate bounded writer grants.
Reviewer, Adversary, and PM/Dispatcher are non-writing. Runtime cannot broaden
a grant. No role writes .git, stages, or commits. The host Git broker validates
each writer's exact delta against that writer's Pilot grant and records the
resulting evidence through Pilot.

## Provenance and status

The supervised-local substrate is valid evidence of local Runtime/App Server
operation under explicit operator supervision. It is not proof of the frozen
fresh-specialist lifecycle or unattended hardening. Historical upstream source
and the retained Apache LICENSE and NOTICE are provenance/licensing material,
not architectural authority or an upstream-compatibility obligation.

