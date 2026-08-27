const NLM_ARTIFACT_SOURCE = "notebooklm-webapp-bridge";
const NLM_ARTIFACT_HOST = "http://127.0.0.1:8765";

async function nlmArtifactFetchJson(url, options = {}, timeoutMs = 10000) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const response = await fetch(url, { ...options, signal: controller.signal });
    const data = await response.json().catch(() => ({ ok:false, error:`HTTP_${response.status}` }));
    if (!response.ok || !data?.ok) throw new Error(data?.error || `HTTP_${response.status}`);
    return data;
  } finally { clearTimeout(timer); }
}

async function nlmArtifactWait(localTaskId, timeoutMs = 150000) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    await new Promise(r => setTimeout(r, 1800));
    try {
      const r = await nlmArtifactFetchJson(`${NLM_ARTIFACT_HOST}/result?taskId=${encodeURIComponent(localTaskId)}`, {}, 5000);
      const state = String(r?.state || "").toUpperCase();
      if (state === "DONE") return r;
      if (state === "ERROR") throw new Error(r?.error || r?.result?.stderr || "LOCAL_ARTIFACT_MIRROR_ERROR");
    } catch (error) {
      if (Date.now() >= deadline) throw error;
    }
  }
  throw new Error("LOCAL_ARTIFACT_MIRROR_TIMEOUT");
}

function nlmArtifactTask(originalTaskId, artifactType, startedAtEpochMs) {
  const suffix = Date.now();
  const localTaskId = `LOCAL_ARTIFACT_MIRROR_${String(originalTaskId || "TASK").replace(/[^A-Za-z0-9_.-]/g,"_")}_${suffix}`;
  return {
    localTaskId,
    task: {
      taskId: localTaskId,
      TASK_ID: localTaskId,
      taskType: "LOCAL_POWERSHELL",
      TASK_TYPE: "LOCAL_POWERSHELL",
      timeoutSeconds: 180,
      TIMEOUT_SECONDS: 180,
      sourceText: JSON.stringify({
        repo: "8friend8ship-cloud/notebooklm-webapp-bridge",
        branch: "main",
        script: "local-agent/governor/MirrorNotebookLMArtifactToDrive.ps1",
        args: {
          TaskId: String(originalTaskId || ""),
          ArtifactType: String(artifactType || "OTHER"),
          StartedAtEpochMs: Number(startedAtEpochMs || Date.now()),
          TimeoutSeconds: 120
        }
      })
    }
  };
}

async function nlmMirrorArtifact(message) {
  const originalTaskId = String(message?.taskId || "");
  const artifactType = String(message?.artifactType || "OTHER");
  if (!originalTaskId) throw new Error("ARTIFACT_TASK_ID_REQUIRED");
  const prepared = nlmArtifactTask(originalTaskId, artifactType, message?.startedAtEpochMs);
  const started = await nlmArtifactFetchJson(`${NLM_ARTIFACT_HOST}/run`, {
    method:"POST",
    headers:{"Content-Type":"application/json"},
    body:JSON.stringify({ source:NLM_ARTIFACT_SOURCE, task:prepared.task })
  }, 10000);
  const final = await nlmArtifactWait(prepared.localTaskId, 150000);
  const inner = final?.result || {};
  const stdout = String(inner?.stdout || "").trim();
  let mirror = null;
  try { mirror = stdout ? JSON.parse(stdout.split(/\r?\n/).filter(Boolean).at(-1)) : null; } catch {}
  return { ok:true, localTaskId:prepared.localTaskId, started, finalState:final?.state || "DONE", mirror, raw:inner };
}

globalThis.__NLM_MIRROR_ARTIFACT_TO_DRIVE__ = nlmMirrorArtifact;
chrome.runtime.onConnect.addListener((port) => {
  if (port?.name !== "NLM_ARTIFACT_MIRROR_V3") return;
  let handled=false;
  port.onMessage.addListener(async (message) => {
    if (handled) return;
    handled=true;
    try {
      if (message?.source !== NLM_ARTIFACT_SOURCE || message?.type !== "MIRROR_ARTIFACT_TO_DRIVE_V3") {
        port.postMessage({ok:false,error:`ARTIFACT_MIRROR_PORT_BAD_MESSAGE type=${String(message?.type||"")} source=${String(message?.source||"")}`});
        return;
      }
      const result=await nlmMirrorArtifact(message);
      port.postMessage(result);
    } catch (error) {
      try { port.postMessage({ok:false,error:String(error?.message||error)}); } catch {}
    }
  });
});

