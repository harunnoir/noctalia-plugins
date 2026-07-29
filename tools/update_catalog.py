#!/usr/bin/env python3
"""Regenerate catalog.toml from every top-level plugin.toml."""
from __future__ import annotations

import json
import tomllib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FIELDS = (
    "id", "name", "version", "author", "license", "icon", "description",
    "deprecated", "plugin_api", "tags", "dependencies",
)


def toml_value(value):
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, int):
        return str(value)
    if isinstance(value, str):
        return json.dumps(value, ensure_ascii=False)
    if isinstance(value, list):
        return "[" + ", ".join(toml_value(item) for item in value) + "]"
    raise TypeError(f"unsupported TOML value: {type(value).__name__}")


rows = []
for manifest_path in sorted(ROOT.glob("*/plugin.toml")):
    with manifest_path.open("rb") as handle:
        manifest = tomllib.load(handle)
    row = {field: manifest[field] for field in FIELDS if field in manifest}
    if not row.get("id") or not row.get("name") or not isinstance(row.get("plugin_api"), int):
        raise SystemExit(f"invalid catalog metadata: {manifest_path}")
    rows.append(row)

lines = [
    "# Generated from plugin manifests by tools/update_catalog.py.",
    "# Keep this file committed for custom Git source discovery.",
    "",
]
for row in rows:
    lines.append("[[plugin]]")
    for field in FIELDS:
        if field in row:
            lines.append(f"{field} = {toml_value(row[field])}")
    lines.append("")

(ROOT / "catalog.toml").write_text("\n".join(lines), encoding="utf-8")
print(f"wrote {ROOT / 'catalog.toml'} with {len(rows)} plugin(s)")
