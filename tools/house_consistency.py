#!/usr/bin/env python3
"""Keep every house state the same house: damage only shows *inside* Calm's
outline (dark holes, cracks, broken glass), never as missing roof or walls.
Resting is the Calm house at night. Rewrites Art/houses.json in place.

    python3 tools/house_consistency.py && python3 tools/sprites.py
"""
import json, os

P = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "Art", "houses.json")
d = json.load(open(P))
S = {s["name"]: s for s in d["sprites"]}
calm = S["Calm"]["grid"]
SKY = set(".KCqzyY")          # clouds, moon, zzz, sun may sit in the sky


def house(y, x):
    """Calm's house body: chimney, roof and walls (not the tree, flowers or sky)."""
    return 5 <= x <= 23 and 4 <= y <= 28 and calm[y][x] != "." and not (y < 7 and calm[y][x] in "yYcC")


def fix(name, hole):
    g = [list(r) for r in S[name]["grid"]]
    for y in range(32):
        for x in range(32):
            c, cc = g[y][x], calm[y][x]
            if house(y, x):
                if c in ".i":   # missing chunk, or rain painted over the house (the app animates rain)
                    g[y][x] = cc if not hole or cc == "o" else "x"
            elif y < 26 and calm[y][x] == "." and c not in SKY:
                g[y][x] = "."   # stray debris / scaffold / rain in the sky
    S[name]["grid"] = ["".join(r) for r in g]


fix("Stressed", hole=False)
fix("Overloaded", hole=True)
fix("Crumbling", hole=True)
old = S["Resting"]["grid"]
S["Resting"]["grid"] = ["".join(old[y][x] if old[y][x] in "qz" else "." if (y < 7 and calm[y][x] in "yYcC") else calm[y][x]
                                for x in range(32)) for y in range(32)]
S["Resting"]["caption"] = "You stepped away to rest - the house is quiet and mending overnight."

for n, s in S.items():
    assert not [1 for y in range(32) for x in range(32) if house(y, x) and s["grid"][y][x] == "."], n

with open(P, "w") as f:
    f.write('{"palette": ' + json.dumps(d["palette"]) + ',\n "sprites": '
            + json.dumps(d["sprites"], indent=1).replace("\n", "\n ") + "\n}\n")
