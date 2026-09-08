# Codex token accounting

This note documents App Server protocol interpretation only. It does not
define lifecycle state, PM persistence, role freshness, or scheduler
authority.

Codex may report both cumulative thread usage and the latest increment. Treat
the event type and payload path as authoritative for interpretation; a field
named usage is not sufficient. Prefer an explicitly cumulative
thread/tokenUsage/updated value for live reporting and do not add its
increment a second time. Treat turn-completed usage as event-specific unless
its relationship to an accepted cumulative total is established.

Account observed usage by the protocol execution identity that supplied it.
A session or thread may span several turns when the current Runtime
implementation does so, but this note does not require a particular PM
session, specialist reuse policy, or crash/restart mechanism.

Token metrics are Runtime observation. They cannot establish role execution,
lifecycle acceptance, convergence, commit authorization, or task completion.

