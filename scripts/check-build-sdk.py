#!/usr/bin/env python3
"""Check the SDK recorded in each architecture of a macOS binary."""
import re
import subprocess
import sys


def version(value):
    parts = tuple(map(int, value.split(".")))
    return parts + (0,) * (3 - len(parts))


expected = subprocess.check_output(["xcrun", "--sdk", "macosx", "--show-sdk-version"], text=True).strip()
metadata = subprocess.check_output(["xcrun", "vtool", "-show-build", sys.argv[1]], text=True)
recorded = re.findall(r"^\s+sdk ([\d.]+)$", metadata, re.MULTILINE)
if not recorded or any(version(value) != version(expected) for value in recorded):
    raise SystemExit(f"SDK mismatch: expected {expected}, recorded {recorded}")
print(f"Linked SDK {expected} verified for {len(recorded)} architecture(s)")
