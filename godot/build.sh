#!/bin/sh
# Export the web build and add a strict Content-Security-Policy.
set -e
GODOT=${GODOT:-../Godot_v4.5.2-stable_linux.x86_64}
mkdir -p export
"$GODOT" --headless --export-release "Web" export/index.html
python3 - <<'PY'
import re, hashlib, base64
p = 'export/index.html'
h = open(p).read()
hashes = []
for m in re.finditer(r'<script(?![^>]*\bsrc=)[^>]*>(.*?)</script>', h, re.S):
    hashes.append("'sha256-" + base64.b64encode(hashlib.sha256(m.group(1).encode()).digest()).decode() + "'")
csp = ("default-src 'none'; script-src 'self' 'wasm-unsafe-eval' " + " ".join(hashes) +
       "; connect-src 'self'; img-src 'self' data: blob:; style-src 'self' 'unsafe-inline'; "
       "worker-src 'self' blob:; media-src 'self' blob:; manifest-src 'self'; base-uri 'none'; form-action 'none'")
meta = '<meta http-equiv="Content-Security-Policy" content="' + csp + '">\n<meta name="referrer" content="no-referrer">\n'
h = h.replace('<head>', '<head>\n' + meta, 1)
open(p, 'w').write(h)
print('CSP script hashes:', len(hashes))
PY
