# SQLite fixture provenance

`pilot_control_plane_v2.sqlite3` was generated mechanically by
`scripts/generate_pilot_fixture.py` from:

- producer repository: `symphony-pilot`
- producer commit: `e39ddd272dff4860b657e00066243d80e69b651b`
- producer schema version: `2`
- producer migration lineage: `[1, "control-plane-v1"], [2, "control-plane-v2-storage-reservations"]`

The producer commit above is historical fixture provenance. The accepted live
integration pair is Pilot `a88b075fb0ab60af369b377992c98706affd3b5e` with
Runtime `bca0d7027c49ef9bc62ee07de0bf669b8d3cb3d6`; the checked-in fixture
continues to represent the same current v2 schema contract without changing
the fixture artifact.

The generator imports the accepted pilot `runtime/control_db.py`, verifies the
producer checkout HEAD, creates tasks and a project blocker through pilot's
host API, closes the database, and copies the resulting SQLite file. Runtime
tests consume only this checked-in artifact; they do not discover or import a
sibling pilot checkout.
