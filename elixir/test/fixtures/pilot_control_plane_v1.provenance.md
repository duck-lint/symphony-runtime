# SQLite fixture provenance

`pilot_control_plane_v1.sqlite3` was generated mechanically by
`scripts/generate_pilot_fixture.py` from:

- producer repository: `symphony-pilot`
- producer commit: `40fcef7e6711daedb8900427a4fdc31fa1322f58`
- producer schema version: `1`
- producer migration identity: `control-plane-v1`

The generator imports the accepted pilot `runtime/control_db.py`, verifies the
producer checkout HEAD, creates tasks and a project blocker through pilot's
host API, closes the database, and copies the resulting SQLite file. Runtime
tests consume only this checked-in artifact; they do not discover or import a
sibling pilot checkout.
