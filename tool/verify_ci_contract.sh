#!/usr/bin/env bash
set -euo pipefail

ci_file="${1:-.github/workflows/ci.yml}"

python3 - "$ci_file" <<'PY'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")


def named_step(name: str) -> str:
    pattern = rf"(?ms)^\s*- name: {re.escape(name)}\s*$.*?(?=^\s*- name:|\Z)"
    match = re.search(pattern, text)
    if match is None:
        raise SystemExit(f"missing workflow step: {name}")
    return match.group(0)


example = named_step("Analyze example (required static analysis)")
if "flutter analyze --no-fatal-warnings" not in example:
    raise SystemExit("example analysis must preserve warnings but fail on errors")
if re.search(r"(?m)^\s*continue-on-error\s*:", example):
    raise SystemExit("example analysis must be a blocking step")

android = named_step("Build Android example (required compile gate)")
if re.search(r"(?m)^\s*continue-on-error\s*:", android):
    raise SystemExit("Android release build must be a blocking step")

summary = re.search(r"(?ms)^  summary:\s*$.*\Z", text)
if summary is None:
    raise SystemExit("missing summary job")
needs = re.search(r"^\s*needs:\s*\[(.*?)\]", summary.group(0), re.MULTILINE)
if needs is None or "android-build" not in needs.group(1):
    raise SystemExit("summary job must depend on android-build")
if needs is None or "workflow-contract" not in needs.group(1):
    raise SystemExit("summary job must depend on workflow-contract")

print(f"CI workflow contract OK: {path}")
PY
