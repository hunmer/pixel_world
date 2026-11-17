from pathlib import Path
import os, subprocess, re, sys
root=Path('E:/pixel_world')
out=root/'.tmp/building_palette_checks'
out.mkdir(exist_ok=True)
env=os.environ.copy()
env['BREAKPOINT_RUNTIME_PORT']='19081'
tests=['builtin_building_assets','map_editor_building_palette','map_editor_building','building_visual','user_asset_editor','map_editor_region_ops','map_editor_ui','editor_region_preset_store','editor_region_clipboard']
failed=False
lines=[]
for name in tests:
 try:
  result=subprocess.run(['D:/Godot/Godot_v4.7.2-stable_win64_console.exe','--headless','--path',str(root),'--script','res://tests/'+name+'_contract.gd'],cwd=str(root),env=env,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=75)
  text=result.stdout.decode('utf-8',errors='replace')
  (out/(name+'.log')).write_text(text,encoding='utf-8')
  errors=re.findall(r'^.*(?:SCRIPT ERROR|Parse Error|Compile Error|FAIL:|ERROR:).*$' ,text,re.M)
  runtime_errors=[e for e in errors if 'resources still in use at exit' not in e]
  ok=result.returncode==0 and not runtime_errors
  line=f'{name}: {"PASS" if ok else "FAIL"} exit={result.returncode} shutdown_resource_warnings={len(errors)-len(runtime_errors)}'
  print(line,flush=True)
  lines.append(line)
  if not ok:
   print('\n'.join(runtime_errors),flush=True)
   failed=True
 except subprocess.TimeoutExpired as error:
  (out/(name+'.log')).write_bytes(error.stdout or b'')
  print(name+': TIMEOUT',flush=True)
  failed=True
(out/'summary.txt').write_text('\n'.join(lines)+'\n',encoding='utf-8')
sys.exit(1 if failed else 0)
