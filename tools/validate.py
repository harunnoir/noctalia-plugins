#!/usr/bin/env python3
"""Small source-repository validator using only Python's standard library."""
from __future__ import annotations

import json
import re
import struct
import sys
import tomllib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
VALID_TAGS = {
    "bar", "desktop", "launcher", "panel", "service", "shortcut",
    "ai", "animation", "audio", "clock", "countdown", "demo",
    "development", "emoticon", "fun", "gaming", "hardware", "indicator",
    "language", "media", "music", "network", "privacy", "productivity",
    "recording", "system", "theming", "time", "utility", "video", "wallpaper",
    "hyprland", "labwc", "mangowc", "niri", "sway",
    "arch", "debian", "fedora", "gentoo", "nixos", "opensuse", "void",
}
SEMVER = re.compile(r"^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:[-+][0-9A-Za-z.-]+)?$")
ID_RE = re.compile(r"^[a-z0-9][a-z0-9._-]*/[a-z0-9][a-z0-9._-]*$")


def fail(message):
    print(f"ERROR: {message}", file=sys.stderr)
    raise SystemExit(1)


def webp_size(path: Path):
    data = path.read_bytes()
    if len(data) < 30 or data[:4] != b"RIFF" or data[8:12] != b"WEBP":
        fail(f"{path} is not a WebP file")
    offset = 12
    while offset + 8 <= len(data):
        kind = data[offset:offset+4]
        size = struct.unpack_from("<I", data, offset + 4)[0]
        payload = data[offset + 8:offset + 8 + size]
        if kind == b"VP8X" and len(payload) >= 10:
            width = 1 + int.from_bytes(payload[4:7], "little")
            height = 1 + int.from_bytes(payload[7:10], "little")
            return width, height
        if kind == b"VP8 " and len(payload) >= 10:
            marker = payload.find(b"\x9d\x01\x2a")
            if marker >= 0 and marker + 7 <= len(payload):
                width = int.from_bytes(payload[marker+3:marker+5], "little") & 0x3FFF
                height = int.from_bytes(payload[marker+5:marker+7], "little") & 0x3FFF
                return width, height
        if kind == b"VP8L" and len(payload) >= 5 and payload[0] == 0x2F:
            bits = int.from_bytes(payload[1:5], "little")
            return (bits & 0x3FFF) + 1, ((bits >> 14) & 0x3FFF) + 1
        offset += 8 + size + (size & 1)
    fail(f"could not read WebP dimensions from {path}")


def keys_from_manifest(value):
    found = []
    if isinstance(value, dict):
        for key, item in value.items():
            if key in {"label_key", "description_key"} and isinstance(item, str):
                found.append(item)
            found.extend(keys_from_manifest(item))
    elif isinstance(value, list):
        for item in value:
            found.extend(keys_from_manifest(item))
    return found


catalog_path = ROOT / "catalog.toml"
if not catalog_path.is_file():
    fail("catalog.toml is missing")
with catalog_path.open("rb") as handle:
    catalog = tomllib.load(handle)
catalog_rows = {row["id"]: row for row in catalog.get("plugin", []) if "id" in row}

plugin_dirs = sorted(path.parent for path in ROOT.glob("*/plugin.toml"))
if not plugin_dirs:
    fail("no plugin directories found")

for plugin_dir in plugin_dirs:
    with (plugin_dir / "plugin.toml").open("rb") as handle:
        manifest = tomllib.load(handle)

    plugin_id = manifest.get("id", "")
    if not ID_RE.match(plugin_id):
        fail(f"invalid plugin id: {plugin_id!r}")
    plugin_name = plugin_id.split("/", 1)[1]
    if plugin_dir.name != plugin_name:
        fail(f"directory {plugin_dir.name!r} must match id suffix {plugin_name!r}")
    if not manifest.get("name"):
        fail(f"{plugin_id}: missing name")
    if not isinstance(manifest.get("plugin_api"), int) or manifest["plugin_api"] <= 0:
        fail(f"{plugin_id}: plugin_api must be a positive integer")
    if not SEMVER.match(str(manifest.get("version", ""))):
        fail(f"{plugin_id}: version is not semver")
    if len(manifest.get("description", "")) > 120:
        fail(f"{plugin_id}: description exceeds 120 characters")

    invalid_tags = set(manifest.get("tags", [])) - VALID_TAGS
    if invalid_tags:
        fail(f"{plugin_id}: invalid tags: {sorted(invalid_tags)}")

    for required in ("README.md", "thumbnail.webp", "translations/en.json"):
        if not (plugin_dir / required).is_file():
            fail(f"{plugin_id}: missing {required}")

    width, height = webp_size(plugin_dir / "thumbnail.webp")
    if (width, height) != (960, 540):
        fail(f"{plugin_id}: thumbnail must be 960x540, got {width}x{height}")

    translations = json.loads((plugin_dir / "translations/en.json").read_text(encoding="utf-8"))
    missing_keys = sorted(set(keys_from_manifest(manifest)) - set(translations))
    if missing_keys:
        fail(f"{plugin_id}: untranslated manifest keys: {missing_keys}")

    readme = (plugin_dir / "README.md").read_text(encoding="utf-8")
    for dependency in manifest.get("dependencies", []):
        if f"`{dependency}`" not in readme:
            fail(f"{plugin_id}: README does not mention dependency {dependency!r}")
    for panel in manifest.get("panel", []):
        command = f"noctalia msg panel-toggle {plugin_id}:{panel['id']}"
        if command not in readme:
            fail(f"{plugin_id}: README is missing panel command: {command}")

    row = catalog_rows.get(plugin_id)
    if row is None:
        fail(f"{plugin_id}: missing from catalog.toml")
    for field in ("name", "version", "author", "license", "icon", "description", "deprecated", "plugin_api", "tags", "dependencies"):
        if manifest.get(field) != row.get(field):
            fail(f"{plugin_id}: catalog field {field!r} does not match plugin.toml")

print(f"validated {len(plugin_dirs)} plugin(s)")
