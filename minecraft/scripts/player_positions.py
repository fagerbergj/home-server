#!/usr/bin/env python3
"""Show last logout position for each Minecraft player.

Usage:
    python3 player_positions.py [/path/to/data]

Defaults to ../data relative to this script (i.e. minecraft/data).
Requires: pip install nbt
"""

import json
import os
import sys

try:
    import nbt
except ImportError:
    print("Missing dependency: pip install nbt", file=sys.stderr)
    sys.exit(1)


def load_usercache(data_dir):
    path = os.path.join(data_dir, "usercache.json")
    if not os.path.exists(path):
        return {}
    with open(path) as f:
        cache = json.load(f)
    return {entry["uuid"]: entry["name"] for entry in cache}


def main():
    data_dir = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
        os.path.dirname(__file__), "..", "data"
    )
    data_dir = os.path.abspath(data_dir)

    playerdata_dir = os.path.join(data_dir, "world", "playerdata")
    if not os.path.isdir(playerdata_dir):
        print(f"playerdata directory not found: {playerdata_dir}", file=sys.stderr)
        sys.exit(1)

    uuid_to_name = load_usercache(data_dir)

    players = []
    for fname in sorted(os.listdir(playerdata_dir)):
        if not fname.endswith(".dat") or fname.endswith(".dat_old"):
            continue
        uuid = fname[:-4]
        path = os.path.join(playerdata_dir, fname)
        try:
            n = nbt.nbt.NBTFile(path)
            pos = n["Pos"]
            x, y, z = float(pos[0].value), float(pos[1].value), float(pos[2].value)
            dim = str(n["Dimension"].value) if "Dimension" in n else "unknown"
            name = uuid_to_name.get(uuid, uuid)
            players.append((name, x, y, z, dim))
        except Exception as e:
            print(f"  Warning: could not read {fname}: {e}", file=sys.stderr)

    if not players:
        print("No player data found.")
        return

    name_w = max(len(p[0]) for p in players)
    print(f"{'Player':<{name_w}}  {'X':>8}  {'Y':>6}  {'Z':>8}  Dimension")
    print("-" * (name_w + 40))
    for name, x, y, z, dim in sorted(players, key=lambda p: p[0].lower()):
        dim = dim.replace("minecraft:", "")
        print(f"{name:<{name_w}}  {x:>8.1f}  {y:>6.1f}  {z:>8.1f}  {dim}")


if __name__ == "__main__":
    main()
