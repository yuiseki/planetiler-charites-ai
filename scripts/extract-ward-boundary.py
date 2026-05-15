#!/usr/bin/env python3
"""Extract Tokyo ward polygons from MLIT N03 GeoJSON.

Usage:
    extract-ward-boundary.py <preset> <n03_geojson> <out_geojson>

Presets:
    taito     -- Taito-ku only (JIS 13106)
    tokyo23   -- all 23 special wards (JIS 13101..13123)
    <jis>     -- a single JIS code (e.g. "13104" for Shinjuku)
"""
import json
import sys


def main() -> int:
    if len(sys.argv) != 4:
        print(__doc__, file=sys.stderr)
        return 2
    preset, src, dst = sys.argv[1], sys.argv[2], sys.argv[3]

    if preset == "taito":
        target = {"13106"}
    elif preset == "tokyo23":
        target = {f"131{i:02d}" for i in range(1, 24)}
    elif preset.isdigit():
        target = {preset}
    else:
        print(f"unknown preset: {preset}", file=sys.stderr)
        return 2

    with open(src, encoding="utf-8") as f:
        d = json.load(f)
    features = [
        f for f in d["features"]
        if (f["properties"].get("N03_007") or "") in target
    ]
    out = {"type": "FeatureCollection", "features": features}
    with open(dst, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False)
    print(f"wrote {dst} ({len(features)} feature(s))")
    return 0


if __name__ == "__main__":
    sys.exit(main())
