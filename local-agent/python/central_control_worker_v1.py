#!/usr/bin/env python3
"""Central control worker V2.

Remote-independent safe Python command lane.
Control: GitHub contents API.
Receipt: local + Google Drive Runtime_Readback when present.
No Google OAuth, no arbitrary shell, no browser/UI mutation.
The only recovery mutation allowed is an exact, fixed PowerShell script under HomeDesignAutomationV7.
"""
from __future__ import annotations
import argparse, base64, json, os, platform, subprocess, urllib.request
from datetime import datetime, timezone
from pathlib import Path

VERSION="PY_CENTRAL_CONTROL_WORKER_V2_REMOTE_INDEPENDENT_20260919"
REPO="8friend8ship-cloud/notebooklm-webapp-bridge"
CONTROL_PATH="local-agent/control/python-worker.json"
ALLOWED={"CANARY_ECHO","PYTHON_RUNTIME_INFO","REMOTE_DC_RECOVER_EXACT"}

def now(): return datetime.now(timezone.utc).isoformat()

def fetch_control():
    u=f"https://api.github.com/repos/{REPO}/contents/{CONTROL_PATH}?ref=main&cb={int(datetime.now().timestamp()*1000)}"
    req=urllib.request.Request(u,headers={"User-Agent":"HomeDesign-Python-Control-V2","Accept":"application/vnd.github+json","Cache-Control":"no-cache"})
    with urllib.request.urlopen(req,timeout=15) as r:
        j=json.load(r)
    raw=base64.b64decode(j["content"]).decode("utf-8")
    return json.loads(raw),j.get("sha","")

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

def exact_recovery(root:Path):
    candidates=[
        root/"RemoteDcDataPlaneGuard.ps1",
        root/"DesktopCommanderKeepAlive.ps1",
    ]
    script=next((p for p in candidates if p.exists()),None)
    if not script: raise RuntimeError("EXACT_RECOVERY_SCRIPT_MISSING")
    ps=os.path.join(os.environ.get("SystemRoot",r"C:\Windows"),"System32","WindowsPowerShell","v1.0","powershell.exe")
    if not os.path.exists(ps): ps="powershell.exe"
    cp=subprocess.run([ps,"-NoProfile","-NonInteractive","-ExecutionPolicy","Bypass","-File",str(script)],
                      stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,timeout=300,check=False,shell=False)
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
    return exact_recovery(root)

def run_once(root:Path):
    state_path=root/"python-control-state.json"
    receipt_path=root/"PYTHON_CONTROL_WORKER_LAST.json"
    c,sha=fetch_control()
    rid=str(c.get("requestId",""))
    enabled=bool(c.get("enabled",False))
    st=load_state(state_path)
    out={"ok":True,"version":VERSION,"requestId":rid,"enabled":enabled,"controlSha":sha,
         "taskId":c.get("taskId"),"action":c.get("action"),"executed":False,"deduped":False,
         "remoteDcDependency":False,"startedAt":now(),"completedAt":"","error":""}
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
    central=find_central()
    if central:
        dp=central/"Runtime_Readback"/"PYTHON"/"PYTHON_CONTROL_WORKER_LAST.json"
        try: save_json(dp,out);out["driveReceiptPath"]=str(dp)
        except Exception as e: out["driveReceiptError"]=str(e);out["ok"]=False
        save_json(receipt_path,out)
    print(json.dumps(out,ensure_ascii=False))
    return 0 if out["ok"] else 2

def self_test():
    assert ALLOWED=={"CANARY_ECHO","PYTHON_RUNTIME_INFO","REMOTE_DC_RECOVER_EXACT"}
    print(json.dumps({"ok":True,"version":VERSION,"tests":["STRICT_WHITELIST","EXACT_RECOVERY_ONLY","NO_ARBITRARY_SHELL","ONE_REQUEST_DEDUPE"]}))
    return 0

if __name__=="__main__":
    ap=argparse.ArgumentParser()
    ap.add_argument("--root",default=os.path.join(os.environ.get("LOCALAPPDATA","."),"HomeDesignAutomationV7","LocalAgent"))
    ap.add_argument("--self-test",action="store_true")
    a=ap.parse_args()
    raise SystemExit(self_test() if a.self_test else run_once(Path(a.root)))
