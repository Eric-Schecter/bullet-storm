#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
if [ -z "${GODOT_BIN:-}" ]; then
  if command -v godot >/dev/null 2>&1; then GODOT_BIN=godot
  else GODOT_BIN=/Applications/Godot.app/Contents/MacOS/Godot; fi
fi
if [ ! -f .export_templates/web_nothreads_release.zip ]; then
  for attempt in 1 2 3; do
    if python3 tools/fetch_web_template.py; then break; fi
    rm -f .export_templates/web_nothreads_release.zip
  done
  test -s .export_templates/web_nothreads_release.zip
fi
mkdir -p build/web
"$GODOT_BIN" --headless --editor --import --quit
"$GODOT_BIN" --headless --export-release Web build/web/index.html
cp assets/cover/bullet-storm-cover.png build/web/cover.png
cp assets/icon.svg build/web/favicon.svg
cp build/web/index.icon.png build/web/favicon.png
cp assets/select.wav build/web/hover.wav
cp assets/audio/nier-hacking/player_shoot.wav build/web/press.wav
python3 - <<'PY'
from pathlib import Path
import zipfile, hashlib, json
web=Path('build/web'); pack=web/'index.pck'
name='game-'+hashlib.sha256(pack.read_bytes()).hexdigest()[:12]+'.pck'
for p in web.glob('game-*.pck'): p.unlink()
pack.rename(web/name)
p=web/'index.html';p.write_text(p.read_text().replace('const canvas=', 'config.mainPack='+json.dumps(name)+';\nconst canvas=',1))
with zipfile.ZipFile('build/Bullet-Storm-Web.zip','w',zipfile.ZIP_DEFLATED) as z:
 for p in sorted(web.iterdir()):
  if p.is_file(): z.write(p,p.name)
PY
