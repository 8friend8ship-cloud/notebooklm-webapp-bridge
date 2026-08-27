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

function nlmArtifactExpectedExtensions(artifactType) {
  const map = {
    AUDIO_OVERVIEW: [".mp3", ".wav", ".m4a", ".ogg", ".mp4"],
    VIDEO_OVERVIEW: [".mp4", ".webm", ".mov"],
    SLIDES: [".pdf", ".pptx"],
    REPORT: [".pdf", ".docx", ".txt"],
    DATA_TABLE: [".xlsx", ".csv"],
    INFOGRAPHIC: [".png", ".jpg", ".jpeg", ".webp", ".pdf"],
    MIND_MAP: [".pdf", ".png", ".json"],
    FLASHCARDS: [".pdf", ".csv", ".txt"],
    QUIZ: [".pdf", ".txt", ".csv"]
  };
  return map[String(artifactType || "OTHER").toUpperCase()] || [".mp3", ".wav", ".m4a", ".mp4", ".webm", ".pdf", ".pptx", ".xlsx", ".csv", ".png", ".jpg", ".jpeg", ".webp", ".docx", ".txt", ".json"];
}

function nlmArtifactExtension(filename) {
  const clean = String(filename || "").split(/[?#]/, 1)[0].toLowerCase();
  const index = clean.lastIndexOf(".");
  return index >= 0 ? clean.slice(index) : "";
}

async function nlmFindCompletedDownload(startedAtEpochMs, artifactType, timeoutMs = 120000) {
  if (!chrome.downloads?.search) return { ok:false, error:"CHROME_DOWNLOADS_API_UNAVAILABLE" };
  const startMs = Math.max(0, Number(startedAtEpochMs || Date.now()) - 3000);
  const startedAfter = new Date(startMs).toISOString();
  const expected = new Set(nlmArtifactExpectedExtensions(artifactType));
  const deadline = Date.now() + Math.max(5000, Number(timeoutMs || 120000));
  let recent = [];

  while (Date.now() < deadline) {
    const items = await chrome.downloads.search({ startedAfter, orderBy:["-startTime"], limit:20 });
    recent = (items || []).map((item) => ({
      id:item.id,
      filename:String(item.filename || ""),
      state:String(item.state || ""),
      exists:item.exists !== false,
      fileSize:Number(item.fileSize || 0),
      totalBytes:Number(item.totalBytes || 0),
      startTime:item.startTime || "",
      endTime:item.endTime || "",
      error:item.error || ""
    }));

    const complete = recent.find((item) => {
      if (item.state !== "complete" || !item.exists || Math.max(item.fileSize, item.totalBytes) <= 0) return false;
      if (!item.filename || /\.crdownload$|\.tmp$/i.test(item.filename)) return false;
      const ext = nlmArtifactExtension(item.filename);
      return expected.has(ext);
    });
    if (complete) return { ok:true, sourcePath:complete.filename, download:complete, recent:recent.slice(0,5) };

    const interrupted = recent.find((item) => item.state === "interrupted");
    if (interrupted) return { ok:false, error:"CHROME_DOWNLOAD_INTERRUPTED", download:interrupted, recent:recent.slice(0,5) };
    await new Promise((resolve) => setTimeout(resolve, 500));
  }

  return { ok:false, error:"CHROME_DOWNLOAD_NOT_FOUND_OR_INCOMPLETE", recent:recent.slice(0,5) };
}

function nlmArtifactTask(originalTaskId, artifactType, startedAtEpochMs, sourcePath = "") {
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
          SourcePath: String(sourcePath || ""),
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

  let sourcePath = String(message?.sourcePath || "");
  let downloadEvidence = null;
  if (!sourcePath) {
    downloadEvidence = await nlmFindCompletedDownload(message?.startedAtEpochMs, artifactType, Number(message?.downloadTimeoutMs || 120000));
    if (!downloadEvidence?.ok || !downloadEvidence?.sourcePath) {
      throw new Error(downloadEvidence?.error || "ARTIFACT_EXACT_DOWNLOAD_PATH_NOT_FOUND");
    }
    sourcePath = downloadEvidence.sourcePath;
  }

  const prepared = nlmArtifactTask(originalTaskId, artifactType, message?.startedAtEpochMs, sourcePath);
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
  return { ok:true, localTaskId:prepared.localTaskId, sourcePath, downloadEvidence, started, finalState:final?.state || "DONE", mirror, raw:inner };
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
