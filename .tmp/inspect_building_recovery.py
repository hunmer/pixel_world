import difflib
import json
from pathlib import Path

block_ids = (7, 8, 9, 10, 11, 14, 15, 17, 18)
roots = [Path(r"C:/Users/Administrator/.tmp") / f"restore_b{n}.txt" for n in block_ids]
project = Path(r"E:/pixel_world")
out_root = project / ".tmp" / "recovered"
owned = {
	"scripts/assets/user_asset_visual_adapter.gd",
	"scripts/iso/battlefield_renderer.gd",
	"scripts/iso/isometric_terrain_3d.gd",
	"scripts/editor/editor_canvas.gd",
	"scripts/editor/asset_library_panel.gd",
}
contents = {path: (project / path).read_text(encoding="utf-8") for path in owned}
originals = dict(contents)
ops = []
for root in roots:
	lines = root.read_text(encoding="utf-8").splitlines()
	for index, line in enumerate(lines[:-1]):
		if line not in ("[assistant • edit]", "[assistant • write]"):
			continue
		try:
			args = json.loads(lines[index + 1])
		except json.JSONDecodeError:
			continue
		path = str(args.get("file_path", "")).replace("\\", "/")
		if path in owned:
			ops.append((root.stem, line, path, args))

failures = []
for number, (block, kind, path, args) in enumerate(ops, 1):
	if kind == "[assistant • write]":
		contents[path] = str(args["content"])
		continue
	old = str(args["old_string"])
	new = str(args["new_string"])
	count = contents[path].count(old)
	expected = 1
	if count < expected:
		failures.append((number, block, path, old, new))
		print(f"FAIL {number:03d} {block} {path} old={len(old)}")
		continue
	if args.get("replace_all", False):
		contents[path] = contents[path].replace(old, new)
	else:
		contents[path] = contents[path].replace(old, new, 1)
	print(f"OK   {number:03d} {block} {path}")

for path in sorted(owned):
	target = out_root / path
	target.parent.mkdir(parents=True, exist_ok=True)
	target.write_text(contents[path], encoding="utf-8")
	diff = "".join(difflib.unified_diff(
		originals[path].splitlines(True), contents[path].splitlines(True),
		fromfile="current/" + path, tofile="recovered/" + path,
	))
	(out_root / (Path(path).name + ".diff")).write_text(diff, encoding="utf-8")
	print(f"WROTE {target} diff_lines={len(diff.splitlines())}")
print(f"TOTAL {len(ops)} FAILURES {len(failures)}")
if failures:
	(out_root / "failures.json").write_text(json.dumps([
		{"number": n, "block": b, "path": p, "old": old, "new": new}
		for n, b, p, old, new in failures
	], ensure_ascii=False, indent=2), encoding="utf-8")
