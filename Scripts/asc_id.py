#!/usr/bin/env python3
"""Read one App Store Connect resource id from CLI text or JSON on stdin."""

from __future__ import annotations

import json
import sys


def _blocks(text: str) -> list[str]:
    chunks = []
    current: list[str] = []
    for line in text.splitlines():
        if line.startswith("-- ") and line.endswith(" --"):
            if current:
                chunks.append("\n".join(current))
            current = [line]
        else:
            current.append(line)
    if current:
        chunks.append("\n".join(current))
    return chunks


def _field(block: str, label: str) -> str | None:
    prefix = label + ":"
    for line in block.splitlines():
        stripped = line.strip()
        if stripped.startswith(prefix):
            return stripped[len(prefix) :].strip()
    return None


def from_text(text: str, kind: str, identifier: str) -> str | None:
    label = "Bundle id" if kind == "app" else "Identifier"
    for block in _blocks(text):
        if _field(block, label) != identifier:
            continue
        resource_id = _field(block, "Id")
        if resource_id:
            return resource_id
    return None


def _walk(node):
    if isinstance(node, dict):
        yield node
        for value in node.values():
            yield from _walk(value)
    elif isinstance(node, list):
        for item in node:
            yield from _walk(item)


def from_json(text: str, kind: str, identifier: str) -> str | None:
    start_candidates = [index for index in (text.find("["), text.find("{")) if index >= 0]
    if not start_candidates:
        return None
    try:
        data = json.loads(text[min(start_candidates) :])
    except json.JSONDecodeError:
        return None
    id_key = "bundleId" if kind == "app" else "identifier"
    for node in _walk(data):
        attributes = node.get("attributes") if isinstance(node, dict) else None
        if not isinstance(attributes, dict):
            continue
        if attributes.get(id_key) == identifier and node.get("id"):
            return str(node["id"])
    return None


def main() -> None:
    if len(sys.argv) != 3 or sys.argv[1] not in {"app", "bundle"}:
        raise SystemExit("usage: asc_id.py app|bundle IDENTIFIER")
    kind, identifier = sys.argv[1], sys.argv[2]
    text = sys.stdin.read()
    resource_id = from_json(text, kind, identifier) or from_text(text, kind, identifier)
    if not resource_id:
        raise SystemExit(1)
    print(resource_id)


if __name__ == "__main__":
    main()
