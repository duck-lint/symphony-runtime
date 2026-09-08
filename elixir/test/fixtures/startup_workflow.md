---
pilot:
  database_path: "/mnt/f/PROJECT-REPOS/symphony/symphony-pilot/test/fixtures/pilot_control_plane_v3.sqlite3"
  project_slug: alpha
  reconcile_command: ["python3", "/opt/symphony-pilot/runtime/reconcile.py", "--profile", "/opt/symphony-pilot/profile.toml"]
workspace:
  root: "/tmp/symphony-workspaces"
  materialize_command: ["git", "clone", "https://github.com/example/alpha.git", "."]
  repository_remote: "https://github.com/example/alpha.git"
polling:
  interval_ms: 1000
agent:
  max_concurrent_agents: 1
codex:
  command: codex app-server
---

Test workflow.
