#!/usr/bin/env python3
"""Central control worker V2.

Remote-independent safe Python command lane.
Control: GitHub contents API.
Receipt: local + Google Drive Runtime_Readback when present.
No Google OAuth, no arbitrary shell, no browser/UI mutation.
The only recovery mutation allowed is an exact, fixed PowerShell script under HomeDesignAutomationV7.
"""
from __future__ import annotations
import argparse, base64, json, os, platform, re, subprocess, time, urllib.request
from datetime import datetime, timezone, timedelta
from pathlib import Path

VERSION="PY_CENTRAL_CONTROL_WORKER_V6_RECORD_RECONCILE_20261009"
REPO="8friend8ship-cloud/notebooklm-webapp-bridge"
CONTROL_PATH="local-agent/control/python-worker.json"
QUEUE_CONTROL_PATH="local-agent/control/notebook-local-queue.json"
ALLOWED={"CANARY_ECHO","PYTHON_RUNTIME_INFO","REMOTE_DC_RECOVER_EXACT","LOCAL_CONSUMER_PERSISTENCE_REPAIR"}

def now(): return datetime.now(timezone.utc).isoformat()

def fetch_control():
    cb=int(datetime.now().timestamp()*1000)
    u=f"https://api.github.com/repos/{REPO}/contents/{CONTROL_PATH}?ref=main&cb={cb}"
    req=urllib.request.Request(u,headers={"User-Agent":"HomeDesign-Python-Control-V3","Accept":"application/vnd.github+json","Cache-Control":"no-cache"})
    try:
        with urllib.request.urlopen(req,timeout=15) as r:
            j=json.load(r)
        raw=base64.b64decode(j["content"]).decode("utf-8")
        return json.loads(raw),j.get("sha","")
    except Exception as api_error:
        raw_url=f"https://raw.githubusercontent.com/{REPO}/main/{CONTROL_PATH}?cb={cb}"
        raw_req=urllib.request.Request(raw_url,headers={"User-Agent":"HomeDesign-Python-Control-V3","Cache-Control":"no-cache"})
        try:
            with urllib.request.urlopen(raw_req,timeout=15) as r:
                raw=r.read().decode("utf-8")
            return json.loads(raw),"RAW_FALLBACK"
        except Exception as raw_error:
            raise RuntimeError(f"CONTROL_FETCH_FAILED api={api_error} raw={raw_error}")

def find_central():
    for letter in "DEFGHIJKLMNOPQRSTUVWXYZ":
        for pre in ["","My Drive","내 드라이브","Google Drive"]:
            p=Path(f"{letter}:\\")/(pre if pre else "")/"00_중앙에이전트"
            if p.exists(): return p
    return None

def save_json(path,obj):
    path.parent.mkdir(parents=True,exist_ok=True)
    payload=json.dumps(obj,ensure_ascii=False,indent=2)
    tmp=path.with_name(path.name+f".{os.getpid()}.tmp")
    tmp.write_text(payload,encoding="utf-8")
    last=None
    for _ in range(20):
        try:
            os.replace(tmp,path)
            return
        except PermissionError as e:
            last=e
            time.sleep(0.1)
    # Windows/Drive-sync fallback: target may allow direct write while denying rename/delete-share.
    for _ in range(20):
        try:
            with open(path,"w",encoding="utf-8",newline="\n") as fh:
                fh.write(payload)
                fh.flush()
                os.fsync(fh.fileno())
            try:
                tmp.unlink(missing_ok=True)
            except Exception:
                pass
            return
        except PermissionError as e:
            last=e
            time.sleep(0.1)
    try:
        tmp.unlink(missing_ok=True)
    except Exception:
        pass
    if last:
        raise last

def write_internal_heartbeat(root:Path, phase:str, extra=None):
    """Refresh the existing persistence heartbeat from the scheduled Python control lane."""
    try:
        hb={
            "ok":True,
            "version":"CENTRAL_INTERNAL_HEARTBEAT_V2_PYTHON_CONTROL_20261009",
            "workerVersion":VERSION,
            "phase":str(phase),
            "updatedAt":now(),
            "pid":os.getpid(),
            "source":"PYTHON_CONTROL_SCHEDULED_HEARTBEAT"
        }
        if isinstance(extra,dict):
            hb.update(extra)
        save_json(root/"CENTRAL_INTERNAL_HEARTBEAT.json",hb)
        return True
    except Exception:
        return False

def load_state(p):
    try:return json.loads(p.read_text(encoding="utf-8-sig"))
    except:return {}

def run_fixed_ps(root:Path, names:list[str], timeout:int=600):
    script=next((root/name for name in names if (root/name).exists()),None)
    if not script: raise RuntimeError("FIXED_SCRIPT_MISSING:"+",".join(names))
    ps=os.path.join(os.environ.get("SystemRoot",r"C:\\Windows"),"System32","WindowsPowerShell","v1.0","powershell.exe")
    if not os.path.exists(ps): ps="powershell.exe"
    flags=getattr(subprocess,"CREATE_NO_WINDOW",0x08000000)
    cp=subprocess.run([ps,"-NoProfile","-NonInteractive","-WindowStyle","Hidden","-ExecutionPolicy","Bypass","-File",str(script)],
                      stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,timeout=timeout,check=False,shell=False,creationflags=flags)
    tail=(cp.stdout or "")[-4000:]
    return script,cp.returncode,tail

def fetch_queue_control():
    u=f"https://api.github.com/repos/{REPO}/contents/{QUEUE_CONTROL_PATH}?ref=main&cb={int(datetime.now().timestamp()*1000)}"
    req=urllib.request.Request(u,headers={"User-Agent":"HomeDesign-Python-Queue-V3","Accept":"application/vnd.github+json","Cache-Control":"no-cache"})
    try:
        with urllib.request.urlopen(req,timeout=15) as r:
            j=json.load(r)
        return json.loads(base64.b64decode(j["content"]).decode("utf-8")),"GITHUB"
    except Exception:
        return None,"NONE"

def claim_drive_queue(central:Path|None, root:Path):
    q=None;doc=None;source="NONE"
    if central:
        q=central/"Runtime_Readback"/"QUEUE"/"NOTEBOOK_LOCAL_QUEUE.json"
        if q.exists():
            try: doc=json.loads(q.read_text(encoding="utf-8-sig"));source="DRIVE_SYNC"
            except Exception as e: raise RuntimeError("QUEUE_PARSE_ERROR:"+str(e))
    if doc is None:
        doc,source=fetch_queue_control()
    if doc is None: return None
    if str(doc.get("status","")).upper()!="READY": return None
    if str(doc.get("target","")).upper() not in ("BOOK-1HE2THGKRA",""):
        raise RuntimeError("QUEUE_TARGET_NOT_ALLOWED")
    if str(doc.get("taskType","")).upper()!="NOTEBOOK_LOCAL_CONSUMER_PERSISTENCE_REPAIR":
        raise RuntimeError("QUEUE_TASK_TYPE_NOT_ALLOWED")
    task_id=str(doc.get("taskId",""))
    if task_id!="TASK_20260919_LOCAL_CONSUMER_PERSISTENCE_REPAIR_001":
        raise RuntimeError("QUEUE_TASK_ID_NOT_ALLOWED")
    claimed=dict(doc);claimed["status"]="CLAIMED";claimed["claimedAt"]=now();claimed["claimedBy"]=VERSION;claimed["queueSource"]=source
    if q is not None: save_json(q,claimed)
    script,rc,tail=run_fixed_ps(root,["INSTALL_AUTO_RESUME_TASK.ps1"],900)
    result={"taskId":task_id,"script":str(script),"exitCode":rc,"outputTail":tail}
    done=dict(claimed);done["completedAt"]=now();done["result"]=result;done["status"]="DONE" if rc==0 else "ERROR"
    if q is not None: save_json(q,done)
    return done

def exact_recovery(root:Path):
    candidates=[
        root/"RemoteDcDataPlaneGuard.ps1",
        root/"DesktopCommanderKeepAlive.ps1",
    ]
    script=next((p for p in candidates if p.exists()),None)
    if not script: raise RuntimeError("EXACT_RECOVERY_SCRIPT_MISSING")
    ps=os.path.join(os.environ.get("SystemRoot",r"C:\Windows"),"System32","WindowsPowerShell","v1.0","powershell.exe")
    if not os.path.exists(ps): ps="powershell.exe"
    flags=getattr(subprocess,"CREATE_NO_WINDOW",0x08000000)
    cp=subprocess.run([ps,"-NoProfile","-NonInteractive","-WindowStyle","Hidden","-ExecutionPolicy","Bypass","-File",str(script)],
                      stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,timeout=300,check=False,shell=False,creationflags=flags)
    tail=(cp.stdout or "")[-4000:]
    if cp.returncode not in (0,4):
        raise RuntimeError(f"RECOVERY_SCRIPT_EXIT_{cp.returncode}:{tail}")
    return {"script":str(script),"exitCode":cp.returncode,"outputTail":tail,
            "meaning":"0=local recovery healthy;4=attempt made but cloud verification still required"}

def execute(c,root:Path):
    action=str(c.get("action","")).upper()
    if action not in ALLOWED: raise RuntimeError("ACTION_NOT_WHITELISTED")
    if action=="CANARY_ECHO":
        payload=str(c.get("payload",""))
        if len(payload)>512: raise RuntimeError("PAYLOAD_TOO_LARGE")
        return {"echo":payload}
    if action=="PYTHON_RUNTIME_INFO":
        return {"pythonVersion":platform.python_version(),"executable":os.path.abspath(os.sys.executable),"platform":platform.platform()}
    if action=="LOCAL_CONSUMER_PERSISTENCE_REPAIR":
        script,rc,tail=run_fixed_ps(root,["INSTALL_AUTO_RESUME_TASK.ps1"],900)
        if rc!=0: raise RuntimeError(f"PERSISTENCE_REPAIR_EXIT_{rc}:{tail}")
        return {"script":str(script),"exitCode":rc,"outputTail":tail}
    return exact_recovery(root)

def audit_scheduled_tasks(root:Path):
    try:
        exe=os.path.join(os.environ.get("SystemRoot",r"C:\\Windows"),"System32","schtasks.exe")
        flags=getattr(subprocess,"CREATE_NO_WINDOW",0x08000000)
        cp=subprocess.run([exe,"/Query","/FO","LIST","/V"],
                          stdout=subprocess.PIPE,stderr=subprocess.STDOUT,
                          text=True,encoding="mbcs",errors="replace",
                          timeout=120,check=False,shell=False,creationflags=flags)
        p=root/"SCHEDULED_TASKS_FULL_AUDIT.txt"
        p.write_text(cp.stdout or "",encoding="utf-8",errors="replace")
        return {"ok":cp.returncode==0,"exitCode":cp.returncode,"path":str(p)}
    except Exception as e:
        return {"ok":False,"error":repr(e)}

KST=timezone(timedelta(hours=9))
def kst_now():
    return datetime.now(KST).isoformat()

def _fragments(text:str):
    if not text: return []
    parts=re.split(r"(?:\s*;\s*|\s*->\s*|\s*→\s*|\n+|(?<=[.!?])\s+)", text)
    out=[]
    for x in parts:
        x=re.sub(r"\s+"," ",x).strip(" -\t")
        if x and x not in out: out.append(x)
    return out

def _lane(text:str):
    t=text.lower()
    if any(k in t for k in ["gui","screen","window","chrome","remote","remotedc","visual","gemini eye","제미나이눈","화면"]):
        return "GUI_OR_GEMINI_EYE"
    if any(k in t for k in ["powershell","service","scheduled task","process","registry","파워썰","프로세스","예약"]):
        return "POWERSHELL_LOCAL"
    if any(k in t for k in ["file","json","log","hash","api","sheet","drive","record","verify","cross","search","파일","로그","시트","드라이브","검수","기록","크로스"]):
        return "PYTHON_API"
    return "OPENAI_REASONING"

def openai_step_plan(root:Path, continuity_path:Path|None=None):
    cp=continuity_path or (Path(os.environ.get("USERPROFILE","."))/"HomeDesignAutomationV7"/"CentralRemotePack"/"OPENAI_CHAT_CONTINUITY_STATE_V1.json")
    record_reconcile=_reconcile_continuity_from_records(cp)
    st=load_state(cp)
    summary=str(st.get("last_received_user_instruction_summary",""))
    first=str(st.get("first_unfinished",""))
    status=str(st.get("status",""))
    fragments=_fragments(summary)
    complex_keywords=("complex","복잡","순차","분할","cross","검수","일관성","library","라이브러리","workflow","작업","대량","반복","분석","배포")
    complex_work=(len(fragments)>3 or len(summary)>=240 or any(k.lower() in summary.lower() for k in complex_keywords))
    steps=[]
    openai_reasoning_used=0
    if first:
        steps.append({"order":1,"stepId":"RECOVER_FIRST_UNFINISHED","description":first,"lane":"PYTHON_API","state":"CURRENT"})
    for frag in fragments:
        if frag==first: continue
        lane=_lane(frag)
        if lane=="OPENAI_REASONING":
            if complex_work or openai_reasoning_used>=3:
                lane="PYTHON_API"
            else:
                openai_reasoning_used+=1
        steps.append({"order":len(steps)+1,"stepId":f"STEP_{len(steps)+1:02d}","description":frag,"lane":lane,"state":"PENDING"})
    resume=str(st.get("resume_after_resource",""))
    if resume and status in ("WAIT_RESOURCE","WAIT_REMOTE_DISCONNECT","INTERRUPTED_THINKING"):
        for frag in _fragments(resume):
            if not any(x["description"]==frag for x in steps):
                lane=_lane(frag)
                if lane=="OPENAI_REASONING":
                    lane="PYTHON_API"
                steps.append({"order":len(steps)+1,"stepId":f"RESUME_{len(steps)+1:02d}","description":frag,"lane":lane,"state":"PENDING_AFTER_RESOURCE"})
    handoff_required=bool(complex_work or len(fragments)>3 or any(x["lane"]!="OPENAI_REASONING" for x in steps))
    out={
        "ok":bool(st and first),
        "version":"OPENAI_PYTHON_STEP_PLANNER_V2_NOTEBOOK_BRAIN_20261007",
        "workerVersion":VERSION,
        "generatedAtKst":kst_now(),
        "timezone":"Asia/Seoul",
        "continuityPath":str(cp),
        "continuityStatus":status,
        "firstUnfinished":first,
        "lastGood":st.get("last_good",[]),
        "instructionSummary":summary,
        "recordReconcile":record_reconcile,
        "complexWork":complex_work,
        "splitRecommended":handoff_required,
        "handoffRequired":handoff_required,
        "maxSequentialBatch":3,
        "openAiReasoningBudget":{
            "maxSimpleReasoningSteps":3,
            "allowed":["USER_COMMUNICATION","USER_APPROVAL","MAX3_SIMPLE_REASONING","CONTRADICTION_ALERT","REFERENCE_ADVICE"],
            "forbiddenBeyondBudget":"OPENAI_DIRECT_COMPLEX_EXECUTION",
            "beyondBudgetRoute":"NOTEBOOK_PYTHON_GEMINI_BRAIN",
            "openAiIsAdvisoryByDefault":True
        },
        "brainArchitecture":{
            "1_USER":"work instruction / approval / correction",
            "2_OPENAI_FRONT_BRAIN":"communication + approval + max3 simple reasoning + advisory only",
            "3_NOTEBOOK_BRAIN":"Python planner/API + Gemini Eye brain/visual QA + AutoResume + Watchdog + PowerShell + Notebook Eye",
            "4_REMOTE_HAND":"RemoteDC GUI exception only, single lane",
            "5_STORAGE_BRAIN":"Drive JSON + Sheets + owner-source runtime receipts",
            "6_DEPLOYED_APP_BRAIN":"after MVP deploy: Vercel AI runtime brain + Firestore state/event brain + Drive call/readback brain; chat is not runtime authority"
        },
        "learningMigration":{
            "goal":"move routine reasoning/execution continuity away from OpenAI chat into notebook and deployed runtime",
            "existingPacks":["PYTHON_PACK","AUTORESUME_PACK","WATCHDOG_PACK","POWERSHELL_PACK","NOTEBOOK_EYE_PACK","GEMINI_EYE"],
            "eachNodeMustRecord":["INPUT","DECISION","ACTION","BEFORE","AFTER","DELTA","EVIDENCE","FAIL_OR_WAIT","FIRST_UNFINISHED","OUTPUT"],
            "promotionRule":"only promote learned behavior after X1/X2 runtime readback; no duplicate pack/node/trigger"
        },
        "nextStep":steps[0] if steps else None,
        "unfinishedSteps":steps,
        "lanePolicy":{
            "PYTHON_API":"default brain for structured/repetitive/complex/log/file/json/hash/api/sheet/Drive analysis and execution planning",
            "POWERSHELL_LOCAL":"OS/service/process/scheduled-task actions through existing approved bridge",
            "GUI_OR_GEMINI_EYE":"Gemini Eye brain/visual/page-context verification; RemoteDC is hand only",
            "OPENAI_REASONING":"only user communication/approval/contradiction and at most 3 simple reasoning steps; advisory by default"
        },
        "executionRule":"USER_TO_OPENAI_MAX3_SIMPLE__BEYOND3_OR_COMPLEX_TO_NOTEBOOK_PYTHON_GEMINI__REMOTE_DC_HAND_ONLY__DRIVE_STATE__VERCELAI_FIRESTORE_DRIVE_AFTER_DEPLOY"
    }
    local=root/"OPENAI_PYTHON_STEP_PLAN_LAST.json"
    save_json(local,out)
    central=find_central()
    if central:
        dp=central/"Runtime_Readback"/"PYTHON"/"OPENAI_PYTHON_STEP_PLAN_LAST.json"
        save_json(dp,out);out["driveReceiptPath"]=str(dp);save_json(local,out)
    print(json.dumps(out,ensure_ascii=False))
    return 0 if out["ok"] else 4

def _read_obj(path:Path):
    try:return json.loads(path.read_text(encoding="utf-8-sig"))
    except:return {}

def _evidence(path:Path, role:str):
    exists=path.exists()
    if not exists:return {"role":role,"path":str(path),"exists":False,"mtimeKst":"","ageSeconds":999999,"state":"MISSING"}
    ts=datetime.fromtimestamp(path.stat().st_mtime,KST)
    age=max(0,int((datetime.now(KST)-ts).total_seconds()))
    obj=_read_obj(path)
    state=str(obj.get("status",obj.get("state",obj.get("managerState","PRESENT"))))
    return {"role":role,"path":str(path),"exists":True,"mtimeKst":ts.isoformat(),"ageSeconds":age,"state":state}

def _latest_first_unfinished(path:Path):
    try:
        lines=path.read_text(encoding="utf-8-sig",errors="replace").splitlines()
        hits=[]
        for i,line in enumerate(lines):
            m=re.match(r"^[ \t]*(?:[-*][ \t]*)?FIRST_UNFINISHED[ \t]*[:=][ \t]*(.*?)[ \t]*$",line,re.I)
            if not m:
                continue
            value=m.group(1).strip().strip("` ")
            if not value:
                j=i+1
                while j<len(lines) and not lines[j].strip():
                    j+=1
                if j<len(lines):
                    value=re.sub(r"^[ \t]*(?:[-*][ \t]*)?","",lines[j]).strip().strip("` ")
            if value:
                hits.append(value)
        return hits[-1] if hits else ""
    except Exception:
        return ""

def _reconcile_continuity_from_records(continuity_path:Path):
    project_root=Path(os.environ.get("USERPROFILE","."))/"HomeDesignAutomationV7"
    central_log_path=project_root/"CentralAgentManager"/"GEMINI_ALL_PROJECT_WORKFLOW_NODELOG_20261003.md"
    ebook_path=project_root/"logs"/"lumi_ebook"/"LUMI_EBOOK_CHAT_APPEND_20260925.md"
    central_first=_latest_first_unfinished(central_log_path)
    ebook_first=_latest_first_unfinished(ebook_path)
    out={
        "ok":False,
        "state":"NO_RECORD_AUTHORITY",
        "continuityPath":str(continuity_path),
        "centralFirstUnfinished":central_first,
        "ebookFirstUnfinished":ebook_first,
        "changed":False
    }
    if not central_first or not ebook_first:
        return out
    if central_first!=ebook_first:
        out["state"]="HOLD_RECORD_AUTHORITY_CONFLICT"
        return out
    st=load_state(continuity_path)
    if not st:
        out["state"]="HOLD_CONTINUITY_MISSING_OR_PARSE_FAIL"
        return out
    current=str(st.get("first_unfinished",""))
    if current==central_first:
        out.update({
            "ok":True,
            "state":"UNCHANGED_RECORD_AUTHORITY_MATCH",
            "firstUnfinished":current,
            "rule":"MATCHING_FIRST_UNFINISHED_VALUE_IS_AUTHORITATIVE; UNRELATED_LOG_MTIME_GROWTH_MUST_NOT_FORCE_CONTINUITY_REWRITE"
        })
        return out
    try:
        latest_record_mtime=max(central_log_path.stat().st_mtime,ebook_path.stat().st_mtime)
        continuity_mtime=continuity_path.stat().st_mtime
    except Exception:
        out["state"]="HOLD_RECORD_MTIME_UNAVAILABLE"
        return out
    if latest_record_mtime<=continuity_mtime+2 and current!=central_first:
        out["state"]="HOLD_CONTINUITY_NEWER_THAN_RECORDS_BUT_VALUE_DIFFERS"
        out["firstUnfinished"]=current
        return out
    previous_summary=str(st.get("last_received_user_instruction_summary",""))
    if previous_summary:
        st["previous_instruction_summary"]=previous_summary
    st["first_unfinished"]=central_first
    st["status"]="WAIT_RESOURCE" if "WAIT_RESOURCE" in central_first else "ACTIVE_UNFINISHED"
    st["last_received_user_instruction_summary"]=(
        "Record-authority continuity reconcile: central nodelog and Lumi ebook agree on FIRST_UNFINISHED="
        +central_first+
        ". Resume only this recorded step after normal preflight. Previous instruction summary is preserved separately."
    )
    st["updated_at"]=kst_now()
    st["record_reconcile"]={
        "version":"OPENAI_CONTINUITY_RECORD_RECONCILE_V1_20261009",
        "atKst":kst_now(),
        "centralFirstUnfinished":central_first,
        "ebookFirstUnfinished":ebook_first,
        "previousFirstUnfinished":current,
        "rule":"MUTATE_ONLY_WHEN_CENTRAL_AND_EBOOK_AGREE_AND_ARE_NEWER_THAN_CONTINUITY"
    }
    save_json(continuity_path,st)
    out.update({"ok":True,"state":"RECONCILED_FROM_MATCHING_NEWER_RECORDS","changed":True,"firstUnfinished":central_first})
    return out


def _execution_expected(first:str):
    u=str(first or "").upper()
    hints=("TRAIN","RUN","EXECUTE","RENDER","SYNC","GENERATE","BUILD","DEPLOY","DOWNLOAD","UPLOAD","TOKENIZE","PROCESS","INGEST","EXPORT","IMPORT")
    return any(h in u for h in hints)

def _live_project_processes(project_root:Path):
    ps=os.path.join(os.environ.get("SystemRoot",r"C:\Windows"),"System32","WindowsPowerShell","v1.0","powershell.exe")
    if not os.path.exists(ps): ps="powershell.exe"
    cmd=(
        "$ErrorActionPreference='SilentlyContinue'; "
        "Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -and "
        "($_.CommandLine -like '*HomeDesignAutomationV7*' -or $_.CommandLine -like '*LumiVoiceRuntime*') } | "
        "Select-Object ProcessId,ParentProcessId,Name,CreationDate,CommandLine | ConvertTo-Json -Compress"
    )
    flags=getattr(subprocess,"CREATE_NO_WINDOW",0x08000000)
    try:
        cp=subprocess.run([ps,"-NoProfile","-NonInteractive","-WindowStyle","Hidden","-Command",cmd],
                          stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,timeout=10,
                          check=False,shell=False,creationflags=flags)
        raw=(cp.stdout or "").strip()
        obj=json.loads(raw) if raw else []
        if isinstance(obj,dict): obj=[obj]
    except Exception:
        obj=[]
    controls=(
        "central_control_worker_v1.py","notebookremoteworkloadsupport.ps1","homedesignautoresume.ps1",
        "openawebsyncguard.ps1","openaiwebsyncguard.ps1","activate-geminieye.ps1",
        "remotemanager","watchdog","monitor-continuous","windowactivitysupervisor","dualmonitorworklane",
        "managedcfttabcleanup.ps1","windowlayoutgovernor.ps1","centralagentpowershellbridge.ps1",
        "desktopcommanderkeepalive.ps1","workloadadmissiongovernor.ps1"
    )
    allowed_names={"python.exe","pythonw.exe","powershell.exe","pwsh.exe","cmd.exe","node.exe","ffmpeg.exe","ffprobe.exe","unrealeditor.exe"}
    rows=[]
    for x in obj:
        cmdline=str(x.get("CommandLine","") or "")
        low=cmdline.lower()
        name=str(x.get("Name","") or "").lower()
        if name not in allowed_names:
            continue
        if "\\appdata\\local\\homedesignautomationv7\\localagent\\" in low:
            continue
        if "\\appdata\\local\\homedesignautomationv7\\desktopcommander\\" in low:
            continue
        if "\\billingaudit\\" in low:
            continue
        if "get-ciminstance win32_process" in low:
            continue
        if any(h in low for h in controls):
            continue
        rows.append({
            "pid":int(x.get("ProcessId",0) or 0),
            "parentPid":int(x.get("ParentProcessId",0) or 0),
            "name":str(x.get("Name","") or ""),
            "creationDate":str(x.get("CreationDate","") or ""),
            "commandLine":cmdline[:1200]
        })
    return rows

def _recent_json_delta(project_root:Path, root:Path):
    state_path=root/"OPENAI_RUNTIME_PID_JSON_STATE.json"
    prev=load_state(state_path)
    prev_map={str(x.get("path","")):x for x in (prev.get("files") or []) if isinstance(x,dict)}
    now_ts=datetime.now().timestamp()
    bases=[
        project_root/"LumiVoiceRuntime",
        project_root/"CentralAgentManager",
        project_root/"CentralRemotePack",
        project_root/"Config"
    ]
    skip={".git","node_modules","venv",".venv","env","__pycache__","site-packages"}
    items=[]
    scanned=0
    for base in bases:
        if not base.exists():
            continue
        for dirpath,dirnames,filenames in os.walk(base):
            dirnames[:]=[n for n in dirnames if n.lower() not in skip]
            for name in filenames:
                if not name.lower().endswith(".json"):
                    continue
                scanned+=1
                if scanned>25000:
                    break
                p=Path(dirpath)/name
                try:
                    st=p.stat()
                except Exception:
                    continue
                age=max(0,int(now_ts-st.st_mtime))
                if age>21600:
                    continue
                old=prev_map.get(str(p),{})
                old_size=old.get("size")
                old_mtime=old.get("mtime")
                delta=(int(st.st_size)-int(old_size)) if isinstance(old_size,(int,float)) else None
                advanced=bool(isinstance(old_mtime,(int,float)) and st.st_mtime>float(old_mtime)+0.0001)
                items.append({
                    "path":str(p),
                    "name":name,
                    "size":int(st.st_size),
                    "deltaBytes":delta,
                    "mtime":float(st.st_mtime),
                    "mtimeKst":datetime.fromtimestamp(st.st_mtime,KST).isoformat(),
                    "ageSeconds":age,
                    "mtimeAdvanced":advanced
                })
            if scanned>25000:
                break
        if scanned>25000:
            break
    items.sort(key=lambda x:x["mtime"],reverse=True)
    items=items[:40]
    growth=[x for x in items if (isinstance(x.get("deltaBytes"),int) and x["deltaBytes"]!=0) or x.get("mtimeAdvanced")]
    results=[x for x in items if any(k in x["name"].upper() for k in ("RESULT","FINAL_QA","REPORT"))]
    snap={"updatedAtKst":kst_now(),"files":[{"path":x["path"],"size":x["size"],"mtime":x["mtime"]} for x in items]}
    save_json(state_path,snap)
    return {
        "statePath":str(state_path),
        "scannedJsonCount":scanned,
        "trackedRecentJsonCount":len(items),
        "jsonDeltaCount":len(growth),
        "jsonDeltas":growth[:12],
        "latestResultJson":results[0] if results else None,
        "baselineCreated":not bool(prev_map)
    }

def _runtime_pid_json_truth(project_root:Path, root:Path, first:str):
    procs=_live_project_processes(project_root)
    js=_recent_json_delta(project_root,root)
    expected=_execution_expected(first)
    latest=js.get("latestResultJson")
    recent_result=bool(latest and int(latest.get("ageSeconds",999999))<=21600)
    if not expected:
        state="NO_EXECUTION_REQUIRED_REVIEW_OR_PLANNING"
        ok=True
    elif procs and int(js.get("jsonDeltaCount",0))>0:
        state="LIVE_PID_AND_JSON_DELTA_CONFIRMED"
        ok=True
    elif procs:
        state="LIVE_PID_NO_JSON_DELTA_WAIT_NOT_ERROR"
        ok=True
    elif recent_result:
        state="PID_FINISHED_RECENT_RESULT_JSON_PRESENT"
        ok=True
    else:
        state="EXPECTED_EXECUTION_BUT_NO_PID_OR_RECENT_RESULT_JSON"
        ok=False
    return {
        "ok":ok,
        "state":state,
        "executionExpected":expected,
        "activeProjectProcessCount":len(procs),
        "activeProjectProcesses":procs[:12],
        "json":js,
        "rule":"RECEIPT_ONLY_PASS_FORBIDDEN__LIVE_PID_PLUS_JSON_DELTA_OR_FINISHED_RESULT_JSON__LIVE_PID_WITHOUT_JSON_DELTA_IS_WAIT_NOT_ERROR"
    }

def openai_cross_validate(root:Path):
    profile=Path(os.environ.get("USERPROFILE","."))
    base=root.parent
    project_root=profile/"HomeDesignAutomationV7"
    continuity_path=project_root/"CentralRemotePack"/"OPENAI_CHAT_CONTINUITY_STATE_V1.json"
    central_log_path=project_root/"CentralAgentManager"/"GEMINI_ALL_PROJECT_WORKFLOW_NODELOG_20261003.md"
    ebook_path=project_root/"logs"/"lumi_ebook"/"LUMI_EBOOK_CHAT_APPEND_20260925.md"
    plan_path=root/"OPENAI_PYTHON_STEP_PLAN_LAST.json"
    three_path=root/"OPENAI_3PACK_SYNC_LAST.json"
    gemini_path=root/"GEMINI_EYE_ACTIVE.json"
    notebook_path=root/"NOTEBOOK_REMOTE_WORKLOAD_SUPPORT_LAST.json"
    ps_path=base/"Runtime_Readback"/"CENTRAL_PS_BRIDGE_LAST.json"
    remote_path=root/"CENTRAL_REMOTE_MANAGER_DISPATCHER_LAST.json"
    keepalive_path=root/"REMOTE_DC_KEEPALIVE_LAST.json"
    record_reconcile=_reconcile_continuity_from_records(continuity_path)
    c=_read_obj(continuity_path); plan=_read_obj(plan_path); three=_read_obj(three_path); gem=_read_obj(gemini_path); nb=_read_obj(notebook_path)
    first=str(c.get("first_unfinished",""))
    central_first=_latest_first_unfinished(central_log_path)
    ebook_first=_latest_first_unfinished(ebook_path)
    record_authority_current=bool(
        record_reconcile.get("ok")
        and first
        and central_first
        and ebook_first
        and first==central_first==ebook_first
    )
    runtime_truth=_runtime_pid_json_truth(project_root,root,first)
    comparisons={
        "continuity_vs_python_plan": bool(first and first==str(plan.get("firstUnfinished",""))),
        "continuity_vs_three_pack": bool(first and first==str((((three.get("latest") or {}).get("continuity") or {}).get("firstUnfinished","")))),
        "continuity_vs_gemini_eye": bool((not gem) or first==str(gem.get("continuityFirstUnfinished",""))),
        "continuity_vs_notebook": bool((not nb) or first==str(nb.get("continuityFirstUnfinished",""))),
        "central_nodelog_vs_ebook": bool(central_first and central_first==ebook_first),
        "continuity_vs_central_nodelog": bool(first and first==central_first),
        "continuity_vs_ebook": bool(first and first==ebook_first),
        "record_authority_current": record_authority_current,
        "runtime_pid_json_truth": bool(runtime_truth.get("ok"))
    }
    evidence=[
        _evidence(continuity_path,"DRIVE_JSON_LOCAL_CANON"),
        _evidence(central_log_path,"CENTRAL_NODELOG"),
        _evidence(ebook_path,"LUMI_EBOOK"),
        _evidence(plan_path,"PYTHON"),
        _evidence(three_path,"THREE_PACK"),
        _evidence(gemini_path,"GEMINI_EYE"),
        _evidence(notebook_path,"NOTEBOOK"),
        _evidence(ps_path,"POWERSHELL"),
        _evidence(remote_path,"REMOTEDC_MANAGER"),
        _evidence(keepalive_path,"REMOTEDC_KEEPALIVE"),
        {
            "role":"LIVE_PID_JSON_RUNTIME",
            "path":str((runtime_truth.get("json") or {}).get("statePath","")),
            "exists":True,
            "mtimeKst":kst_now(),
            "ageSeconds":0,
            "state":str(runtime_truth.get("state","UNKNOWN")),
            "activePids":[int(x.get("pid",0)) for x in (runtime_truth.get("activeProjectProcesses") or [])],
            "jsonDeltaCount":int(((runtime_truth.get("json") or {}).get("jsonDeltaCount",0))),
            "latestResultJson":((runtime_truth.get("json") or {}).get("latestResultJson"))
        }
    ]
    core_roles={"PYTHON","THREE_PACK","GEMINI_EYE","NOTEBOOK","REMOTEDC_MANAGER"}
    core_fresh=all(x["exists"] and x["ageSeconds"]<=900 for x in evidence if x["role"] in core_roles)
    consistent=all(comparisons.values()) and core_fresh
    out={
        "ok":consistent,
        "version":"OPENAI_CROSS_VALIDATION_V3_1_RECORD_VALUE_AUTHORITY_20261009",
        "checkedAtKst":kst_now(),"timezone":"Asia/Seoul",
        "firstUnfinished":first,
        "centralNodeLogFirstUnfinished":central_first,
        "ebookFirstUnfinished":ebook_first,
        "runtimeTruth":runtime_truth,
        "recordReconcile":record_reconcile,
        "comparisons":comparisons,
        "coreFreshWithinSeconds":900,
        "coreFresh":core_fresh,
        "evidence":evidence,
        "rule":"FIRST_UNFINISHED_VALUE_AUTHORITY_MUST_MATCH_CENTRAL_NODELOG_EBOOK_CONTINUITY; UNRELATED_LOG_MTIME_GROWTH_IS_NOT_A_CONFLICT; RECEIPT_ONLY_PASS_FORBIDDEN; LIVE_PID_PLUS_JSON_DELTA_OR_FINISHED_RESULT_JSON_CROSSCHECK_REQUIRED; LIVE_PID_WITHOUT_JSON_DELTA_IS_WAIT_NOT_ERROR; LIVE_RUNTIME_RECEIPTS_USE_900S_FRESHNESS"
    }
    local=root/"OPENAI_CROSS_VALIDATION_LAST.json";save_json(local,out)
    central=find_central()
    if central:
        dp=central/"Runtime_Readback"/"PYTHON"/"OPENAI_CROSS_VALIDATION_LAST.json";save_json(dp,out);out["driveReceiptPath"]=str(dp);save_json(local,out)
    print(json.dumps(out,ensure_ascii=False))
    return 0 if out["ok"] else 4

def run_once(root:Path):
    write_internal_heartbeat(root,"START")
    continuity_path=Path(os.environ.get("USERPROFILE","."))/"HomeDesignAutomationV7"/"CentralRemotePack"/"OPENAI_CHAT_CONTINUITY_STATE_V1.json"
    record_reconcile=_reconcile_continuity_from_records(continuity_path)
    state_path=root/"python-control-state.json"
    receipt_path=root/"PYTHON_CONTROL_WORKER_LAST.json"
    central=find_central()
    queue_result=None
    try:
        queue_result=claim_drive_queue(central,root)
    except Exception as qe:
        queue_result={"status":"ERROR","error":str(qe)}
    task_audit=audit_scheduled_tasks(root)
    c,sha=fetch_control()
    rid=str(c.get("requestId",""))
    enabled=bool(c.get("enabled",False))
    st=load_state(state_path)
    out={"ok":True,"version":VERSION,"requestId":rid,"enabled":enabled,"controlSha":sha,
         "taskId":c.get("taskId"),"action":c.get("action"),"executed":False,"deduped":False,
         "remoteDcDependency":False,"recordReconcile":record_reconcile,"driveQueueClaim":queue_result,"taskAudit":task_audit,"startedAt":now(),"completedAt":"","error":""}
    if not enabled or not rid:
        out["status"]="NO_ACTIVE_REQUEST"
    elif st.get("attemptedRequestId")==rid:
        out["status"]="DEDUPED_ALREADY_ATTEMPTED";out["deduped"]=True
    else:
        try:
            result=execute(c,root)
            out["result"]=result;out["executed"]=True;out["status"]="DONE"
        except Exception as e:
            out["ok"]=False;out["status"]="ERROR";out["error"]=str(e)
        finally:
            save_json(state_path,{"attemptedRequestId":rid,"attemptedAt":now(),"attemptOk":out["ok"],"version":VERSION})
    out["completedAt"]=now()
    save_json(receipt_path,out)
    if central:
        dp=central/"Runtime_Readback"/"PYTHON"/"PYTHON_CONTROL_WORKER_LAST.json"
        try: save_json(dp,out);out["driveReceiptPath"]=str(dp)
        except Exception as e: out["driveReceiptError"]=str(e);out["ok"]=False
        save_json(receipt_path,out)
    write_internal_heartbeat(root,"COMPLETE",{"status":out.get("status",""),"ok":bool(out.get("ok"))})
    print(json.dumps(out,ensure_ascii=False))
    return 0 if out["ok"] else 2

def self_test():
    assert ALLOWED=={"CANARY_ECHO","PYTHON_RUNTIME_INFO","REMOTE_DC_RECOVER_EXACT","LOCAL_CONSUMER_PERSISTENCE_REPAIR"}
    print(json.dumps({"ok":True,"version":VERSION,"tests":["STRICT_WHITELIST","EXACT_RECOVERY_ONLY","DRIVE_QUEUE_READY_TO_CLAIMED","NO_ARBITRARY_SHELL","ONE_REQUEST_DEDUPE","OPENAI_STEP_PLANNER","NOTEBOOK_BRAIN_HANDOFF_MAX3","KST_CROSS_VALIDATION"]}))
    return 0

if __name__=="__main__":
    ap=argparse.ArgumentParser()
    ap.add_argument("--root",default=os.path.join(os.environ.get("LOCALAPPDATA","."),"HomeDesignAutomationV7","LocalAgent"))
    ap.add_argument("--self-test",action="store_true")
    ap.add_argument("--openai-plan",action="store_true")
    ap.add_argument("--cross-validate",action="store_true")
    ap.add_argument("--continuity",default="")
    a=ap.parse_args()
    root=Path(a.root)
    if a.self_test:
        raise SystemExit(self_test())
    if a.openai_plan:
        cp=Path(a.continuity) if a.continuity else None
        raise SystemExit(openai_step_plan(root,cp))
    if a.cross_validate:
        raise SystemExit(openai_cross_validate(root))
    raise SystemExit(run_once(root))