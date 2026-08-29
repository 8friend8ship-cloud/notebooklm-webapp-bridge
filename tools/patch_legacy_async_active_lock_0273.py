from pathlib import Path
import json, subprocess

ROOT = Path(__file__).resolve().parents[1]
runner_path = ROOT / 'notebooklm-webapp-bridge-source-v0.2.0/extension/local-powershell-runner.js'
manifest_path = ROOT / 'notebooklm-webapp-bridge-source-v0.2.0/extension/manifest.json'
release_path = ROOT / 'runtime/stable/release.json'

runner = runner_path.read_text(encoding='utf-8')
start_marker = 'async function pollCore(reason="alarm")'
end_marker = '  await recoverStale(cfg,token,listedTasks);'
start = runner.find(start_marker)
if start < 0:
    raise SystemExit('pollCore start not found')
end = runner.find(end_marker, start)
if end < 0:
    raise SystemExit('recoverStale anchor not found')
end += len(end_marker)

replacement = '''function activeStableTime(active){
  const direct=Number(active?.startedAtMs||active?.claimedAtMs||0);
  if(Number.isFinite(direct)&&direct>0)return direct;
  const derived=taskTime(active?.task||{});
  return Number.isFinite(derived)&&derived>0?derived:0;
}
function queueTaskLiveForActive(t){
  const s=taskStatus(t);
  return ["CLAIMED","STARTED","RUNNING","NOTEBOOK_OPENED"].includes(s);
}
async function reconcileActive(cfg,token,active,listedTasks){
  const id=String(active?.taskId||"");
  if(!id){await setActive(null);return {cleared:true,reason:"LEGACY_ACTIVE_NO_TASK_ID"};}
  const queued=(listedTasks||[]).find(t=>taskId(t)===id)||null;
  if(queued&&!queueTaskLiveForActive(queued)){
    await setActive(null);
    return {cleared:true,reason:`ACTIVE_QUEUE_NOT_LIVE_${taskStatus(queued)}`,taskId:id};
  }
  if(!queued){
    let host=null;try{host=await hostResult(id);}catch{}
    const hs=String(host?.state||"").toUpperCase();
    if(!["RUNNING","STARTED"].includes(hs)){
      await setActive(null);
      return {cleared:true,reason:`ACTIVE_ORPHAN_QUEUE_MISSING_HOST_${hs||"UNKNOWN"}`,taskId:id};
    }
  }
  const stable=activeStableTime(active);
  if(!stable){
    const next={...active,claimedAtMs:Date.now(),legacyTimestampRecovered:true,legacyRecoveredAt:new Date().toISOString()};
    await setActive(next);
    return {cleared:false,active:next,reason:"LEGACY_ACTIVE_TIMESTAMP_ANCHORED"};
  }
  return {cleared:false,active,reason:"ACTIVE_RECONCILED"};
}
async function pollCore(reason="alarm"){
  const cfg=await config();const token=await sessionToken();if(!token){await wakeControlCenter(cfg,"NO_SESSION");return {ok:true,skipped:"no_session",authRefreshRequested:true};}
  let listed;try{listed=await api(cfg.appsScriptUrl,{action:"listTasks",sessionToken:token,includeClaimed:true});}catch(error){if(isSessionError(error)){await clearExpiredSessionAndWake(cfg,error);return {ok:true,reason,skipped:"session_refresh_requested"};}throw error;}
  const listedTasks=Array.isArray(listed.tasks)?listed.tasks:[];
  const active=await getActive();
  if(active){
    const reconciled=await reconcileActive(cfg,token,active,listedTasks);
    if(!reconciled.cleared)return {ok:true,reason,active:await finalize(cfg,token,reconciled.active)};
  }
  await recoverStale(cfg,token,listedTasks);'''

runner = runner[:start] + replacement + runner[end:]
runner_path.write_text(runner, encoding='utf-8')

manifest = json.loads(manifest_path.read_text(encoding='utf-8'))
manifest['version'] = '0.2.73'
manifest['description'] = 'Legacy async active-lock recovery: reconcile persisted LOCAL_POWERSHELL_ASYNC active state with the live queue/Host and clear orphan or non-live locks so READY tasks cannot starve forever. No new permissions, OAuth, normal-Chrome, Generate, or credit behavior.'
manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')

def blob_sha(path: Path) -> str:
    return subprocess.check_output(['git','hash-object',str(path)], text=True).strip()

runner_sha = blob_sha(runner_path)
manifest_sha = blob_sha(manifest_path)
release = json.loads(release_path.read_text(encoding='utf-8'))
release['version'] = '0.2.73'
release['actionId'] = 'APPLY_NOTEBOOKLM_0.2.73_LEGACY_ACTIVE_LOCK_RECOVERY_20260829'
release['releasedAt'] = '2026-08-29T15:20:00+09:00'
release['description'] = 'Reconciles legacy nlmLocalPowerShellAsyncActiveV2 state against the live Apps Script queue and local Host before finalizing. Orphan/non-live persisted locks are cleared, and legacy active records without stable timestamps receive one stable anchor instead of resetting timeout age on every poll. Prevents permanent READY starvation. No new permission, OAuth, download-path, normal-Chrome, Generate, or credit behavior.'
release['sourceCommit'] = 'PENDING_THIS_COMMIT'
for f in release.get('files', []):
    if f.get('path') == 'manifest.json': f['gitBlobSha1'] = manifest_sha
    if f.get('path') == 'local-powershell-runner.js': f['gitBlobSha1'] = runner_sha
release_path.write_text(json.dumps(release, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print(json.dumps({'ok':True,'manifestSha':manifest_sha,'runnerSha':runner_sha,'version':'0.2.73'}))
