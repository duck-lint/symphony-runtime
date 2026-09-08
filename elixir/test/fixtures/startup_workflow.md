---
pilot:
  database_path: "/mnt/f/PROJECT-REPOS/symphony/symphony-pilot/test/fixtures/pilot_control_plane_v3.sqlite3"
  project_slug: alpha
workspace:
  root: "/tmp/symphony-workspaces"
polling:
  interval_ms: 1000
agent:
  max_concurrent_agents: 1
codex:
  command: codex app-server
---

Test workflow.
