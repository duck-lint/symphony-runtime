#!/usr/bin/env python3
"""Generate the checked-in SQLite contract fixture from accepted pilot code.

This is a fixture producer, not a runtime schema implementation. Runtime tests
consume the generated database without importing this script or a sibling
checkout. The producer commit is pinned so regeneration cannot silently use a
different pilot schema.
"""
from __future__ import annotations

import argparse
import importlib.util
import pathlib
import shutil
import subprocess
import sys
import tempfile


PILOT_COMMIT = "40fcef7e6711daedb8900427a4fdc31fa1322f58"
BASE_TIME = "2026-09-01T12:00:00+00:00"
BASE_SHA = "a" * 40


def load_control_db(pilot_root: pathlib.Path):
    pilot_runtime = pilot_root / "runtime"
    sys.path.insert(0, str(pilot_runtime))
    spec = importlib.util.spec_from_file_location("pilot_control_db", pilot_runtime / "control_db.py")
    if spec is None or spec.loader is None:
        raise RuntimeError("could not load accepted pilot control_db.py")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def assert_pilot_commit(pilot_root: pathlib.Path) -> None:
    actual = subprocess.check_output(
        [
            "git",
            "-c",
            f"safe.directory={pilot_root}",
            "-C",
            str(pilot_root),
            "rev-parse",
            "HEAD",
        ],
        text=True,
    ).strip()
    if actual != PILOT_COMMIT:
        raise RuntimeError(f"pilot checkout is {actual}, expected accepted {PILOT_COMMIT}")


def add_task(database, task_id: str, project_slug: str, state: str, title: str):
    return database.create_task(
        task_id=task_id,
        project_slug=project_slug,
        title=title,
        objective=f"Objective for {title}",
        base_ref="main",
        base_sha=BASE_SHA,
        branch=f"codex/{project_slug}-{task_id[:8]}",
        state=state,
        created_at=BASE_TIME,
    )


def generate(pilot_root: pathlib.Path, output: pathlib.Path) -> None:
    assert_pilot_commit(pilot_root)
    control_db = load_control_db(pilot_root)
    output.parent.mkdir(parents=True, exist_ok=True)

    with tempfile.TemporaryDirectory() as temporary:
        source = pathlib.Path(temporary) / "control.sqlite3"
        with control_db.open_database(source) as database:
            add_task(database, "11111111-1111-1111-1111-111111111111", "alpha", "QUEUED", "Alpha queued")
            add_task(database, "22222222-2222-2222-2222-222222222222", "beta", "QUEUED", "Beta queued")
            add_task(
                database,
                "33333333-3333-3333-3333-333333333333",
                "alpha",
                "HUMAN_BLOCKED",
                "Alpha human blocked",
            )
            add_task(
                database,
                "44444444-4444-4444-4444-444444444444",
                "alpha",
                "READY_FOR_HUMAN_MERGE",
                "Alpha ready for merge",
            )
            project_blocked = add_task(
                database,
                "55555555-5555-5555-5555-555555555555",
                "alpha",
                "QUEUED",
                "Alpha project blocked",
            )
            database.record_blocker(
                task_id=project_blocked["id"],
                kind="project",
                body="Project decision pending",
                created_at=BASE_TIME,
            )

        shutil.copy2(source, output)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("pilot_root", type=pathlib.Path)
    parser.add_argument("output", type=pathlib.Path)
    args = parser.parse_args()
    generate(args.pilot_root, args.output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
