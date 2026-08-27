from pathlib import Path
import hashlib, json, subprocess

runner=Path('notebooklm-webapp-bridge-source-v0.2.0/extension/content/notebooklm-runner.js')
s=runner.read_text(encoding='utf-8')
anchor='  async function runAudioOverview(task) {'
if 'async function runExistingAudioArtifactDownload(task)' not in s:
    assert anchor in s, 'AUDIO_FUNCTION_ANCHOR_MISSING'
    block=r'''  async function runExistingAudioArtifactDownload(task) {
    const studio = findDeepControl(["studio","스튜디오"]);
    if (studio) { try { studio.click(); } catch {} await sleep(900); }
    const ready = await waitFor(() => audioOverviewReady(), 30000, 500);
    if (!ready) throw new Error("AUDIO_EXISTING_ARTIFACT_NOT_FOUND_NO_GENERATION");
    const download = await requestAudioArtifactDownload(ready);
    if (!download?.requested) throw new Error(`AUDIO_EXISTING_DOWNLOAD_NOT_TRIGGERED:${download?.reason || "unknown"}`);
    const downloadEvidence = await chrome.runtime.sendMessage({
      source: SOURCE,
      type: "VERIFY_DOWNLOAD_AFTER_CLICK",
      startedAtEpochMs: download.startedAtEpochMs,
      timeoutMs: Math.min(45000, Math.max(15000, Number(task.timeoutSeconds || 30) * 1000))
    });
    if (!downloadEvidence?.ok) throw new Error(`AUDIO_EXISTING_REAL_DOWNLOAD_NOT_VERIFIED:${downloadEvidence?.error || "UNKNOWN"}`);
    return {
      resultText:"AUDIO_EXISTING_DOWNLOAD_VERIFIED",
      resultUrls:[location.href],
      captureMode:"AUDIO_EXISTING_DOWNLOAD_VERIFIED",
      artifactType:"AUDIO_OVERVIEW",
      actualArtifact:{requested:true,download,downloadEvidence},
      notebookUrl:location.href,pageTitle:document.title,capturedAt:new Date().toISOString(),
      status:"DONE",taskId:task.taskId,contentId:task.contentId||"",taskType:task.taskType||"AUDIO_EXISTING_DOWNLOAD"
    };
  }

'''
    s=s.replace(anchor,block+anchor,1)
route='    if (["AUDIO","AUDIO_OVERVIEW","NOTEBOOKLM_AUDIO"].includes(normalizedTaskType)) return runAudioOverview(task);'
existing='    if (["AUDIO_EXISTING_DOWNLOAD","NOTEBOOKLM_AUDIO_EXISTING_DOWNLOAD"].includes(normalizedTaskType)) return runExistingAudioArtifactDownload(task);'
if existing not in s:
    assert route in s, 'AUDIO_ROUTE_ANCHOR_MISSING'
    s=s.replace(route,existing+'\n\n'+route,1)
runner.write_text(s,encoding='utf-8')

manifest=Path('notebooklm-webapp-bridge-source-v0.2.0/extension/manifest.json')
ms=manifest.read_text(encoding='utf-8')
if '"version": "0.2.69"' in ms:
    ms=ms.replace('"version": "0.2.69"','"version": "0.2.70"',1)
elif '"version": "0.2.70"' not in ms:
    raise AssertionError('MANIFEST_VERSION_ANCHOR_MISSING')
manifest.write_text(ms,encoding='utf-8')

def blob_sha(path):
    b=Path(path).read_bytes()
    return hashlib.sha1(f'blob {len(b)}\0'.encode()+b).hexdigest()

release=Path('runtime/stable/release.json')
r=json.loads(release.read_text(encoding='utf-8'))
r['version']='0.2.70'
r['actionId']='APPLY_NOTEBOOKLM_0.2.70_D82_AUDIO_EXISTING_REAL_DOWNLOAD_20260827'
r['releasedAt']='2026-08-27T21:12:00+09:00'
r['requiresUserApproval']=False
r['description']='D82 adds AUDIO_EXISTING_DOWNLOAD: reuse existing audio only, never generate, and complete only after Chrome downloads reports a complete existing nonzero file. No download-path change, file move, OAuth change, normal-Chrome mutation, or new NotebookLM artifact.'
r['sourceCommit']=subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip()
hashes={
 'manifest.json':blob_sha(manifest),
 'content/notebooklm-runner.js':blob_sha(runner)
}
for f in r.get('files',[]):
    if f.get('path') in hashes:
        f['gitBlobSha1']=hashes[f['path']]
release.write_text(json.dumps(r,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
