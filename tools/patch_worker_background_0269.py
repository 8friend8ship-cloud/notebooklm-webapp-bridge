from pathlib import Path
import json, hashlib, subprocess
root=Path('notebooklm-webapp-bridge-source-v0.2.0/extension')
wp=root/'worker.js'
w=wp.read_text(encoding='utf-8')
line='import "./background.js";'
if line not in w:
    w=line+'\n'+w
wp.write_text(w,encoding='utf-8')
mp=root/'manifest.json'
m=json.loads(mp.read_text(encoding='utf-8'))
m['version']='0.2.69'
m['description']='D79 restores the main queue/background runtime import while retaining D78 real Chrome download evidence. Existing-artifact download succeeds only with a completed nonzero browser download; no path change or file move.'
mp.write_text(json.dumps(m,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
def blob(path):
    b=Path(path).read_bytes();return hashlib.sha1(f'blob {len(b)}\0'.encode()+b).hexdigest()
rp=Path('runtime/stable/release.json')
r=json.loads(rp.read_text(encoding='utf-8'))
r['version']='0.2.69'
r['actionId']='APPLY_NOTEBOOKLM_0.2.69_D79_BACKGROUND_RUNTIME_RESTORE_20260827'
r['releasedAt']='2026-08-27T20:21:00+09:00'
r['requiresUserApproval']=False
r['description']='D79 restores background.js import in worker.js and retains D78 real-download verification. No Chrome download-path change, file move, Drive mirror, or NotebookLM generation.'
r['sourceCommit']=subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip()
hashes={'manifest.json':blob(mp),'worker.js':blob(wp)}
for f in r['files']:
    if f['path'] in hashes:f['gitBlobSha1']=hashes[f['path']]
rp.write_text(json.dumps(r,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')