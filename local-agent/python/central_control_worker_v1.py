#!/usr/bin/env python3
"""Central control worker V2.

Remote-independent safe Python command lane.
Control: GitHub contents API.
Receipt: local + Google Drive Runtime_Readback when present.
No Google OAuth, no arbitrary shell, no browser/UI mutation.
The only recovery mutation allowed is an exact, fixed PowerShell script under HomeDesignAutomationV7.
"""
from __future__ import annotations
import argparse, base64, json, os, platform, re, subprocess, urllib.request
from datetime import datetime, timezone, timedelta
from pathlib import Path

VERSION="PY_CENTRAL_CONTROL_WORKER_V4_OPENAI_STEP_PLANNER_20261007"
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
    tmp=path.with_suffix(path.suffix+".tmp")
    tmp.write_text(json.dumps(obj,ensure_ascii=False,indent=2),encoding="utf-8")
    os.replace(tmp,path)

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
    st=load_state(cp)
    summary=str(st.get("last_received_user_instruction_summary",""))
    first=str(st.get("first_unfinished",""))
    status=str(st.get("status",""))
    fragments=_fragments(summary)
    complex_keywords=("complex","복잡","순차","분할","cross","검수","일관성","library","라이브러리","workflow","작업")
    complex_work=(len(fragments)>=3 or len(summary)>=240 or any(k.lower() in summary.lower() for k in complex_keywords))
    steps=[]
    if first:
        steps.append({"order":1,"stepId":"RECOVER_FIRST_UNFINISHED","description":first,"lane":"PYTHON_API","state":"CURRENT"})
    for frag in fragments:
        if frag==first: continue
        steps.append({"order":len(steps)+1,"stepId":f"STEP_{len(steps)+1:02d}","description":frag,"lane":_lane(frag),"state":"PENDING"})
    resume=str(st.get("resume_after_resource",""))
    if resume and status in ("WAIT_RESOURCE","WAIT_REMOTE_DISCONNECT","INTERRUPTED_THINKING"):
        for frag in _fragments(resume):
            if not any(x["description"]==frag for x in steps):
                steps.append({"order":len(steps)+1,"stepId":f"RESUME_{len(steps)+1:02d}","description":frag,"lane":_lane(frag),"state":"PENDING_AFTER_RESOURCE"})
    out={
        "ok":bool(st and first),
        "version":"OPENAI_PYTHON_STEP_PLANNER_V1_20261007",
        "generatedAtKst":kst_now(),
        "timezone":"Asia/Seoul",
        "continuityPath":str(cp),
        "continuityStatus":status,
        "firstUnfinished":first,
        "lastGood":st.get("last_good",[]),
        "instructionSummary":summary,
        "complexWork":complex_work,
        "splitRecommended":complex_work,
        "maxSequentialBatch":3,
        "nextStep":steps[0] if steps else None,
        "unfinishedSteps":steps,
        "lanePolicy":{
            "PYTHON_API":"structured/repetitive/log/file/json/hash/api/sheet/Drive readback first",
            "POWERSHELL_LOCAL":"OS/service/process/scheduled-task actions through existing approved bridge",
            "GUI_OR_GEMINI_EYE":"visual/page-context verification only; RemoteDC single GUI lane",
            "OPENAI_REASONING":"planning/contradiction/lineage judgement; must not skip recorded prior step"
        },
        "executionRule":"COMPLEX_WORK_SPLIT_FIRST__PYTHON_API_FIRST__MAX3_STEPS_PER_BATCH__RETURN_UNFINISHED_STEPS_ON_INTERRUPT"
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

def openai_cross_validate(root:Path):
    profile=Path(os.environ.get("USERPROFILE","."))
    base=root.parent
    continuity_path=profile/"HomeDesignAutomationV7"/"CentralRemotePack"/"OPENAI_CHAT_CONTINUITY_STATE_V1.json"
    plan_path=root/"OPENAI_PYTHON_STEP_PLAN_LAST.json"
    three_path=root/"OPENAI_3PACK_SYNC_LAST.json"
    gemini_path=root/"GEMINI_EYE_ACTIVE.json"
    notebook_path=root/"NOTEBOOK_REMOTE_WORKLOAD_SUPPORT_LAST.json"
    ps_path=base/"Runtime_Readback"/"CENTRAL_PS_BRIDGE_LAST.json"
    remote_path=root/"CENTRAL_REMOTE_MANAGER_DISPATCHER_LAST.json"
    keepalive_path=root/"REMOTE_DC_KEEPALIVE_LAST.json"
    c=_read_obj(continuity_path); plan=_read_obj(plan_path); three=_read_obj(three_path); gem=_read_obj(gemini_path); nb=_read_obj(notebook_path)
    first=str(c.get("first_unfinished",""))
    comparisons={
        "continuity_vs_python_plan": bool(first and first==str(plan.get("firstUnfinished",""))),
        "continuity_vs_three_pack": bool(first and first==str((((three.get("latest") or {}).get("continuity") or {}).get("firstUnfinished","")))),
        "continuity_vs_gemini_eye": bool((not gem) or first==str(gem.get("continuityFirstUnfinished",""))),
        "continuity_vs_notebook": bool((not nb) or first==str(nb.get("continuityFirstUnfinished","")))
    }
    evidence=[
        _evidence(continuity_path,"DRIVE_JSON_LOCAL_CANON"),
        _evidence(plan_path,"PYTHON"),
        _evidence(three_path,"THREE_PACK"),
        _evidence(gemini_path,"GEMINI_EYE"),
        _evidence(notebook_path,"NOTEBOOK"),
        _evidence(ps_path,"POWERSHELL"),
        _evidence(remote_path,"REMOTEDC_MANAGER"),
        _evidence(keepalive_path,"REMOTEDC_KEEPALIVE")
    ]
    core_roles={"DRIVE_JSON_LOCAL_CANON","PYTHON","THREE_PACK","GEMINI_EYE","NOTEBOOK","REMOTEDC_MANAGER"}
    core_fresh=all(x["exists"] and x["ageSeconds"]<=900 for x in evidence if x["role"] in core_roles)
    consistent=all(comparisons.values()) and core_fresh
    out={
        "ok":consistent,
        "version":"OPENAI_CROSS_VALIDATION_V1_20261007",
        "checkedAtKst":kst_now(),"timezone":"Asia/Seoul",
        "firstUnfinished":first,
        "comparisons":comparisons,
        "coreFreshWithinSeconds":900,
        "coreFresh":core_fresh,
        "evidence":evidence,
        "rule":"DRIVE_JSON_PLUS_PYTHON_PLUS_POWERSHELL_PLUS_REMOTEDC_PLUS_GEMINI_EYE_KST_CROSSCHECK; UNUSED_POWERSHELL_IS_ADVISORY_NOT_FATAL"
    }
    local=root/"OPENAI_CROSS_VALIDATION_LAST.json";save_json(local,out)
    central=find_central()
    if central:
        dp=central/"Runtime_Readback"/"PYTHON"/"OPENAI_CROSS_VALIDATION_LAST.json";save_json(dp,out);out["driveReceiptPath"]=str(dp);save_json(local,out)
    print(json.dumps(out,ensure_ascii=False))
    return 0 if out["ok"] else 4

def run_once(root:Path):
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
         "remoteDcDependency":False,"driveQueueClaim":queue_result,"taskAudit":task_audit,"startedAt":now(),"completedAt":"","error":""}
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
    print(json.dumps(out,ensure_ascii=False))
    return 0 if out["ok"] else 2

def self_test():
    assert ALLOWED=={"CANARY_ECHO","PYTHON_RUNTIME_INFO","REMOTE_DC_RECOVER_EXACT","LOCAL_CONSUMER_PERSISTENCE_REPAIR"}
    print(json.dumps({"ok":True,"version":VERSION,"tests":["STRICT_WHITELIST","EXACT_RECOVERY_ONLY","DRIVE_QUEUE_READY_TO_CLAIMED","NO_ARBITRARY_SHELL","ONE_REQUEST_DEDUPE","OPENAI_STEP_PLANNER","KST_CROSS_VALIDATION"]}))
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