from pathlib import Path
import shutil, zipfile
root=Path(__file__).resolve().parents[1]
dist=root/'dist'
if dist.exists(): shutil.rmtree(dist)
dist.mkdir()
with zipfile.ZipFile(dist/'notebooklm-webapp-bridge-extension-v0.2.0.zip','w',zipfile.ZIP_DEFLATED) as z:
    for p in (root/'extension').rglob('*'):
        if p.is_file(): z.write(p,p.relative_to(root/'extension'))
with zipfile.ZipFile(dist/'notebooklm-webapp-bridge-source-v0.2.0.zip','w',zipfile.ZIP_DEFLATED) as z:
    for p in root.rglob('*'):
        if p.is_file() and 'dist' not in p.parts and '.git' not in p.parts: z.write(p,p.relative_to(root))
print(dist)
