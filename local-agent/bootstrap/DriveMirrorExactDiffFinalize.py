import os, json, shutil, subprocess, time
from pathlib import Path
from datetime import datetime

SRC=Path(r'G:\내 드라이브')
BASE=Path(r'F:\CENTRAL_AGENT_DATA')
MIRROR=BASE/'01_ACTIVE'/'GOOGLE_DRIVE_MIRROR'
CTRL=BASE/'00_CONTROL'
QUAR_ROOT=BASE/'99_QUARANTINE'
RECEIPT=CTRL/'DRIVE_MIRROR_EXACT_DIFF_FINALIZE_LAST.json'
FINAL_STATUS=CTRL/'mirror_final_status.json'
RECON_STATUS=CTRL/'reconcile_status.json'
EX={'.gsheet','.gdoc','.gslides','.gform','.gscript','.gprj'}
VOLATILE_PREFIXES=('00_중앙에이전트\\Runtime_Readback\\',)
VOLATILE_BASENAMES={'run_log.jsonl'}
VOLATILE_EXACT={
 'CentralAgent\\Runtime_Recovery\\DrivePackBridge\\DRIVE_PACK_BRIDGE_LAST.json',
 'CentralAgent\\Runtime_Recovery\\SelfReliance\\CENTRAL_SELF_RELIANCE_FORCE_X2.json',
 'Laptop-Recovery\\BOOK-1HE2THGKRA\\LAST_BACKUP_STATUS.json',
 'Laptop-Recovery\\BOOK-1HE2THGKRA\\SYSTEM_INVENTORY\\drivers.csv',
}

def save(o):
    o['updated_at']=datetime.now().astimezone().isoformat(); RECEIPT.parent.mkdir(parents=True,exist_ok=True)
    text=json.dumps(o,ensure_ascii=False,indent=2); RECEIPT.write_text(text,encoding='utf-8')
    cloud=SRC/'00_중앙에이전트'/'Runtime_Readback'
    try:
        if cloud.parent.exists(): cloud.mkdir(parents=True,exist_ok=True); (cloud/RECEIPT.name).write_text(text,encoding='utf-8')
    except Exception: pass

def is_volatile(rel):
    norm=rel.replace('/','\\'); folded=norm.casefold()
    if folded in {x.casefold() for x in VOLATILE_EXACT}: return True
    if any(folded.startswith(p.casefold()) for p in VOLATILE_PREFIXES): return True
    return Path(norm).name.casefold() in VOLATILE_BASENAMES

def inventory(root):
    out={}; originals={}; total=0; skipped=0
    for dp,ds,fs in os.walk(root):
        for f in fs:
            p=Path(dp)/f
            if p.suffix.lower() in EX: continue
            rel=str(p.relative_to(root)).replace('/','\\')
            if is_volatile(rel): skipped+=1; continue
            try: sz=p.stat().st_size
            except OSError: continue
            k=rel.casefold(); out[k]=sz; originals[k]=rel; total+=sz
    return out,originals,total,skipped

def diff():
    s,so,sb,sv=inventory(SRC); m,mo,mb,mv=inventory(MIRROR)
    return {'src_count':len(s),'mirror_count':len(m),'src_bytes':sb,'mirror_bytes':mb,'src_volatile_skipped':sv,'mirror_volatile_skipped':mv,'missing':sorted([so[k] for k in s.keys()-m.keys()]),'extra':sorted([mo[k] for k in m.keys()-s.keys()]),'size_mismatch':sorted([so[k] for k in s.keys()&m.keys() if s[k]!=m[k]])}

def targeted_sync(r):
    targets=list(dict.fromkeys(r['missing']+r['size_mismatch']))
    if len(targets)>100: return {'ran':False,'status':'SAFETY_GATE','count':len(targets)}
    copied=[]
    for rel in targets:
        s=SRC/rel; d=MIRROR/rel
        if not s.exists(): continue
        d.parent.mkdir(parents=True,exist_ok=True); shutil.copy2(str(s),str(d)); copied.append(rel)
    return {'ran':True,'status':'COPIED','count':len(copied),'copied':copied}

def quarantine(extras):
    stamp=datetime.now().strftime('%Y%m%d_%H%M%S'); qroot=QUAR_ROOT/f'DRIVE_MIRROR_DEST_ONLY_{stamp}'; moved=[]
    for rel in extras:
        s=MIRROR/rel; d=qroot/rel
        if not s.exists(): continue
        d.parent.mkdir(parents=True,exist_ok=True); shutil.move(str(s),str(d)); moved.append(rel)
    return str(qroot),moved

state={'version':'DRIVE_MIRROR_EXACT_DIFF_FINALIZE_V3_TARGETED_SYNC_20260911','status':'STARTED','destructive_delete':False,'quarantine_only':True,'volatile_policy':'Runtime_Readback/* + RUN_LOG.jsonl + four exact live status files excluded from static equality; volatile files verified separately by runtime receipts'}; save(state)
if not SRC.exists() or not MIRROR.exists(): state.update(status='FAIL_MOUNT_MISSING',src_exists=SRC.exists(),mirror_exists=MIRROR.exists()); save(state); raise SystemExit(2)
r1=diff(); state['precheck']=r1; save(state)
if r1['src_count']<100000 or r1['mirror_count']<100000: state['status']='FAIL_IMPLAUSIBLE_INVENTORY'; save(state); raise SystemExit(3)
if r1['missing'] or r1['size_mismatch']:
    state['targeted_sync']=targeted_sync(r1); r1=diff(); state['post_targeted_sync']=r1; save(state)
if r1['missing'] or r1['size_mismatch']: state['status']='FAIL_SOURCE_GAPS_REMAIN_NO_QUARANTINE'; save(state); raise SystemExit(4)
if len(r1['extra'])>100: state['status']='FAIL_EXTRA_COUNT_SAFETY_GATE'; save(state); raise SystemExit(5)
if r1['extra']:
    q,m=quarantine(r1['extra']); state['quarantine_path']=q; state['quarantined']=m; save(state)
x1=diff(); time.sleep(3); x2=diff(); state['x1']=x1; state['x2']=x2
clean=lambda x:x['src_count']==x['mirror_count'] and x['src_bytes']==x['mirror_bytes'] and not x['missing'] and not x['extra'] and not x['size_mismatch']
if not(clean(x1) and clean(x2) and x1['src_count']==x2['src_count'] and x1['src_bytes']==x2['src_bytes']): state['status']='FAIL_EXACT_DIFF_X2'; save(state); raise SystemExit(6)
state['exact_diff_x2']='PASS'; save(state)
final={'timestamp':datetime.now().astimezone().isoformat(),'status':'PASS','method':'V3_EXACT_DIFF_X2_NO_REDUNDANT_RESCAN','src_count':x2['src_count'],'mirror_count':x2['mirror_count'],'src_bytes':x2['src_bytes'],'mirror_bytes':x2['mirror_bytes'],'volatile_policy':state['volatile_policy'],'receipt_id':'RCT_20260911_DRIVE_MIRROR_FINALIZER_X2_001'}
FINAL_STATUS.write_text(json.dumps(final,ensure_ascii=False,indent=2),encoding='utf-8'); state['finalizer_receipt']=final; state['finalizer_exit']=0; save(state)
try:
    subprocess.run(['schtasks.exe','/Run','/TN','CentralAgent_Runtime_Reconcile'],capture_output=True,text=True,timeout=30); time.sleep(20)
except Exception as e: state['runtime_reconcile_trigger_error']=str(e)
try: state['runtime_reconcile']=json.loads(RECON_STATUS.read_text(encoding='utf-8-sig'))
except Exception as e: state['runtime_reconcile_error']=str(e)
rr=state.get('runtime_reconcile',{}); recon_pass=(str(rr.get('status','')).upper()=='PASS' or rr.get('ok') is True)
state['status']='VERIFIED_COMPLETE_X2' if recon_pass else 'EXACT_DIFF_X2_PASS_FINAL_RECEIPT_PENDING'; state['receipt_id']='RCT_20260911_DRIVE_MIRROR_FINAL_X2_001'; save(state)
raise SystemExit(0 if state['status']=='VERIFIED_COMPLETE_X2' else 7)
