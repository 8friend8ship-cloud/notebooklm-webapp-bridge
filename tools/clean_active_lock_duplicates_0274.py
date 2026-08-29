from pathlib import Path
import json, subprocess

ROOT=Path(__file__).resolve().parents[1]
runner_path=ROOT/'notebooklm-webapp-bridge-source-v0.2.0/extension/local-powershell-runner.js'
manifest_path=ROOT/'notebooklm-webapp-bridge-source-v0.2.0/extension/manifest.json'
release_path=ROOT/'runtime/stable/release.json'
text=runner_path.read_text(encoding='utf-8')
block_start='function activeStableTime(active){'
first=text.find(block_start)
second=text.find(block_start, first+1) if first>=0 else -1
if first<0:
    raise SystemExit('activeStableTime block missing')
if second>=0:
    # Remove the first duplicate group and keep the later copy adjacent to pollCore.
    text=text[:first]+text[second:]
runner_path.write_text(text,encoding='utf-8')

manifest=json.loads(manifest_path.read_text(encoding='utf-8'))
manifest['version']='0.2.74'
manifest['description']='Clean stable recovery build: retain one queue/Host-aware legacy active-lock reconciler and remove duplicate helper declarations introduced during the 0.2.73 emergency patch. No permission/OAuth/normal-Chrome/Generate/credit behavior change.'
manifest_path.write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')

def sha(p):
    return subprocess.check_output(['git','hash-object',str(p)],text=True).strip()
rsha=sha(runner_path);msha=sha(manifest_path)
release=json.loads(release_path.read_text(encoding='utf-8'))
release['version']='0.2.74'
release['actionId']='APPLY_NOTEBOOKLM_0.2.74_ACTIVE_LOCK_CLEANUP_20260829'
release['releasedAt']='2026-08-29T15:24:00+09:00'
release['description']='Removes duplicate active-lock helper declarations from the 0.2.73 emergency recovery while preserving queue/Host reconciliation and stable timestamp anchoring. No permissions, OAuth, normal Chrome, Generate or credit changes.'
release['sourceCommit']='PENDING_THIS_COMMIT'
for f in release.get('files',[]):
    if f.get('path')=='manifest.json': f['gitBlobSha1']=msha
    if f.get('path')=='local-powershell-runner.js': f['gitBlobSha1']=rsha
release_path.write_text(json.dumps(release,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(json.dumps({'ok':True,'version':'0.2.74','runnerSha':rsha,'manifestSha':msha,'duplicateCount':text.count(block_start)}))
