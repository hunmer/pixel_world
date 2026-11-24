# -*- coding: utf-8 -*-
"""Download the generated image of LibTV node(s).

usage: python fetch.py <node name> [<node name> ...] --out <dir>
Writes <dir>/<node>.png and <dir>/<node>_url.txt. Run from the project root
(the folder holding .libtv/project.json).
"""
import argparse, json, os, subprocess, urllib.request

ap = argparse.ArgumentParser()
ap.add_argument("nodes", nargs="+")
ap.add_argument("--out", required=True)
a = ap.parse_args()
os.makedirs(a.out, exist_ok=True)
for node in a.nodes:
    r = subprocess.run(["libtv", "node", node], capture_output=True, text=True,
                       encoding="utf-8", errors="replace")
    data = json.loads(r.stdout)["data"]
    urls = data.get("url") or []
    if not urls:
        print(node, "no url yet", data.get("taskInfo"))
        continue
    out = os.path.join(a.out, f"{node}.png")
    urllib.request.urlretrieve(urls[0], out)
    with open(os.path.join(a.out, f"{node}_url.txt"), "w") as f:
        f.write(urls[0] + "\n")
    print(node, "->", out)
