import pathlib
import subprocess
import sys

root = pathlib.Path('E:/pixel_world')
engine = 'D:/Godot/Godot_v4.7.2-stable_win64_console.exe'
tracked = subprocess.check_output(['git', 'diff', '--name-only'], cwd=root, text=True).splitlines()
untracked = subprocess.check_output(['git', 'ls-files', '--others', '--exclude-standard'], cwd=root, text=True).splitlines()
paths = sorted({p for p in tracked + untracked if p.endswith('.gd') and not p.startswith('.tmp/')})
failed = []
logs = root / '.tmp/building_parse'
logs.mkdir(exist_ok=True)
for path in paths:
    result = subprocess.run([engine, '--headless', '--path', str(root), '--check-only', '--script', 'res://' + path], cwd=root, capture_output=True, text=True, encoding='utf-8', errors='replace', timeout=30)
    output = result.stdout + result.stderr
    (logs / (path.replace('/', '_') + '.log')).write_text(output, encoding='utf-8')
    bad = result.returncode != 0 or any(mark in output for mark in ('SCRIPT ERROR', 'Parse Error', 'Compile Error'))
    if bad:
        failed.append(path)
        print('FAIL', path, output)
print('CHECK_ONLY scripts=%d failed=%d' % (len(paths), len(failed)))
sys.exit(1 if failed else 0)
