import json, os, re, subprocess, datetime, pathlib, sys
BASE=pathlib.Path(os.environ.get("LOCALAPPDATA",""))/"HomeDesignAutomationV7"/"LocalAgent"
ROOT=BASE/"RecoveryBlueprint"
BLUEPRINT=ROOT/"REMOTE_RECOVERY_BLUEPRINT_V1.json"
STATE=ROOT/"REMOTE_RECOVERY_STATE.json"
ROOT.mkdir(parents=True, exist_ok=True)

def run(args, timeout=20):
    try:
        r=subprocess.run(args,capture_output=True,text=True,errors="ignore",timeout=timeout)
        return r.returncode,(r.stdout or "")+(r.stderr or "")
    except Exception as e:
        return 98,repr(e)

def node(id,name,ok,detail,next_action=""):
    return {"id":id,"name":name,"ok":bool(ok),"detail":detail,"next_action":next_action}

def power_guard():
    rc,out=run(["powercfg","/query","SCHEME_CURRENT","SUB_SLEEP"])
    zero_hits=len(re.findall(r"0x00000000",out))
    ok=(rc==0 and zero_hits>=2)
    return node("N10","POWER_GUARD",ok,{"rc":rc,"zero_hits":zero_hits},"Fix sleep policy" if not ok else "")

def task_topology():
    ps='''$t=Get-ScheduledTask | Where-Object {$_.TaskName -match "HomeDesign|Central|LaptopRecovery"}; $t | ForEach-Object {[pscustomobject]@{TaskName=$_.TaskName;State=[string]$_.State;Action=(($_.Actions|ForEach-Object{$_.Execute+" "+$_.Arguments}) -join " || ")}} | ConvertTo-Json -Depth 5'''
    rc,out=run(["powershell.exe","-NoProfile","-ExecutionPolicy","Bypass","-Command",ps],40)
    unsafe=[]
    try:
        rows=json.loads(out)
        if isinstance(rows,dict): rows=[rows]
        for r in rows:
            act=(r.get("Action") or "").lower()
            if "powershell.exe" in act and "windowstyle hidden" not in act and r.get("State")!="Disabled":
                unsafe.append(r.get("TaskName"))
    except Exception:
        rows=[]
    return node("N20","TASK_TOPOLOGY",rc==0 and not unsafe,{"unsafe_ready_tasks":unsafe,"task_count":len(rows)})

def loop_serialization():
    shim=BASE/"SafeScheduledTaskShim.py"
    txt=shim.read_text(encoding="utf-8",errors="ignore") if shim.exists() else ""
    ok=shim.exists() and "GLOBAL_AUTOMATION.lock" in txt and "CREATE_NO_WINDOW" in txt
    return node("N30","LOOP_SERIALIZATION",ok,{"shim":str(shim)})

def remote_local_chain():
    ps='''$p=@(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object{([string]$_.Name)-match "^(node)(.exe)?$" -and ([string]$_.CommandLine)-match "desktop-commander" -and ([string]$_.CommandLine)-match "(^|\\s)remote(\\s|$)"}); $tcp=0; if($p.Count){$ids=@($p|%{[int]$_.ProcessId});$tcp=@(Get-NetTCPConnection -State Established -ErrorAction SilentlyContinue|Where-Object{$ids -contains $_.OwningProcess}).Count}; [pscustomobject]@{remoteProcessCount=$p.Count;tcpEstablished=$tcp}|ConvertTo-Json'''
    rc,out=run(["powershell.exe","-NoProfile","-NonInteractive","-WindowStyle","Hidden","-ExecutionPolicy","Bypass","-Command",ps],25)
    try:d=json.loads(out)
    except:d={"remoteProcessCount":0,"tcpEstablished":0}
    ok=rc==0 and int(d.get("remoteProcessCount",0))>=1 and int(d.get("tcpEstablished",0))>=1
    return node("N40","REMOTE_LOCAL_CHAIN",ok,d)

def main():
    bp=json.loads(BLUEPRINT.read_text(encoding="utf-8"))
    nodes=[node("N00","LOAD_LAST_GOOD",True,{"blueprint_id":bp["blueprint_id"]}),power_guard(),task_topology(),loop_serialization(),remote_local_chain()]
    first=next((x for x in nodes if not x["ok"]),None)
    state={
      "blueprint_id":bp["blueprint_id"],
      "checked_at":datetime.datetime.now().astimezone().isoformat(),
      "nodes":nodes,
      "first_failed_node":first["id"] if first else "N50",
      "first_unfinished_node":first["id"] if first else "N50",
      "external_next":"N50 AUTH_GATE -> N60 REMOTE_MCP_X2 -> N70 DATA_PLANE_X2 -> N80 TASK_RESTORE -> N90 CONSISTENCY_RECEIPT",
      "rule":"Resume from first failed/unfinished node; do not repeat prior PASS unless dependency changed."
    }
    STATE.write_text(json.dumps(state,ensure_ascii=False,indent=2),encoding="utf-8")
    print(json.dumps(state,ensure_ascii=False,indent=2))
    return 0 if not first else 10

if __name__=="__main__":
    raise SystemExit(main())
