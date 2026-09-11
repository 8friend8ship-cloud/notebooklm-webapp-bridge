import os, json, shutil, subprocess, time
from pathlib import Path
from datetime import datetime

SRC=Path(r'G:\내 드라이브')
BASE=Path(r'F:\CENTRAL_AGENT_DATA')
MIRROR=BASE/'01_ACTIVE'/'GOOGLE_DRIVE_MIRROR'
CTRL=BASE/'00_CONTROL'
QUAR_ROOT=BASE/'99_QUARANTINE'
RECEIPT=CTRL/'DRIVE_MIRROR_EXACT_DIFF_FINALIZE_LAST.json'
FINALIZER=CTRL/'finalize_mirror.py'
FINAL_STATUS=CTRL/'mirror_final_status.json'
RECON_STATUS=CTRL/'reconcile_status.json'
EX={'.gsheet','.gdoc','.gslides','.gform','.gscript','.gprj'}


def save(o):
    o['updated_at']=datetime.now().astimezone().isoformat()
    RECEIPT.parent.mkdir(parents=True, exist_ok=True)
    RECEIPT.write_text(json.dumps(o,ensure_ascii=False,indent=2),encoding='utf-8')
    cloud=SRC/'00_중앙에이전트'/'Runtime_Readback'
    try:
        if cloud.parent.exists():
            cloud.mkdir(parents=True,exist_ok=True)
            (cloud/RECEIPT.name).write_text(json.dumps(o,ensure_ascii=False,indent=2),encoding='utf-8')
    except Exception:
        pass


def inventory(root):
    out={}; originals={}; total=0
    for dp, ds, fs in os.walk(root):
        for f in fs:
            p=Path(dp)/f
            if p.suffix.lower() in EX: continue
            try: sz=p.stat().st_size
            except OSError: continue
            rel=str(p.relative_to(root)).replace('/','\\')
            key=rel.casefold()
            out[key]=sz; originals[key]=rel; total+=sz
    return out, originals, total


def diff():
    s,so,sb=inventory(SRC); m,mo,mb=inventory(MIRROR)
    missing=sorted([so[k] for k in s.keys()-m.keys()])
    extra=sorted([mo[k] for k in m.keys()-s.keys()])
    mismatch=sorted([so[k] for k in s.keys()&m.keys() if s[k]!=m[k]])
    return {'src_count':len(s),'mirror_count':len(m),'src_bytes':sb,'mirror_bytes':mb,'missing':missing,'extra':extra,'size_mismatch':mismatch}


def safe_sync_once():
    p=CTRL/'sync_mirror.py'
    if not p.exists(): return {'ran':False,'exit':None}
    r=subprocess.run(['python',str(p)],capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=1800)
    return {'ran':True,'exit':r.returncode,'stdout':r.stdout[-1000:],'stderr':r.stderr[-1000:]}


def quarantine(extras):
    stamp=datetime.now().strftime('%Y%m%d_%H%M%S')
    qroot=QUAR_ROOT/f'DRIVE_MIRROR_DEST_ONLY_{stamp}'
    moved=[]
    for rel in extras:
        src=MIRROR/rel; dst=qroot/rel
        if not src.exists(): continue
        dst.parent.mkdir(parents=True,exist_ok=True)
        shutil.move(str(src),str(dst)); moved.append(rel)
    return str(qroot), moved

state={'version':'DRIVE_MIRROR_EXACT_DIFF_FINALIZE_V1_20260911','status':'STARTED','destructive_delete':False,'quarantine_only':True}
save(state)
if not SRC.exists() or not MIRROR.exists():
    state.update(status='FAIL_MOUNT_MISSING',src_exists=SRC.exists(),mirror_exists=MIRROR.exists()); save(state); raise SystemExit(2)

r1=diff(); state['precheck']=r1; save(state)
if r1['src_count']<100000 or r1['mirror_count']<100000:
    state['status']='FAIL_IMPLAUSIBLE_INVENTORY'; save(state); raise SystemExit(3)
if r1['missing'] or r1['size_mismatch']:
    state['sync_attempt']=safe_sync_once(); r1=diff(); state['post_sync']=r1; save(state)
if r1['missing'] or r1['size_mismatch']:
    state['status']='FAIL_SOURCE_GAPS_REMAIN_NO_QUARANTINE'; save(state); raise SystemExit(4)
if len(r1['extra'])>100:
    state['status']='FAIL_EXTRA_COUNT_SAFETY_GATE'; save(state); raise SystemExit(5)
if r1['extra']:
    q,moved=quarantine(r1['extra']); state['quarantine_path']=q; state['quarantined']=moved; save(state)

x1=diff(); time.sleep(3); x2=diff(); state['x1']=x1; state['x2']=x2
clean=lambda x: x['src_count']==x['mirror_count'] and x['src_bytes']==x['mirror_bytes'] and not x['missing'] and not x['extra'] and not x['size_mismatch']
if not(clean(x1) and clean(x2) and x1['src_count']==x2['src_count'] and x1['src_bytes']==x2['src_bytes']):
    state['status']='FAIL_EXACT_DIFF_X2'; save(state); raise SystemExit(6)
state['exact_diff_x2']='PASS'; save(state)

if FINALIZER.exists():
    try:
        fr=subprocess.run(['python',str(FINALIZER)],capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=1800)
        state['finalizer_exit']=fr.returncode
    except Exception as e:
        state['finalizer_exception']=str(e)
try: state['finalizer_receipt']=json.loads(FINAL_STATUS.read_text(encoding='utf-8-sig'))
except Exception as e: state['finalizer_receipt_error']=str(e)
try:
    subprocess.run(['schtasks.exe','/Run','/TN','CentralAgent_Runtime_Reconcile'],capture_output=True,text=True,timeout=30)
    time.sleep(20)
except Exception: pass
try: state['runtime_reconcile']=json.loads(RECON_STATUS.read_text(encoding='utf-8-sig'))
except Exception as e: state['runtime_reconcile_error']=str(e)

f=state.get('finalizer_receipt',{}); rr=state.get('runtime_reconcile',{})
final_pass=(str(f.get('status','')).upper()=='PASS')
recon_pass=(str(rr.get('status','')).upper()=='PASS' or rr.get('ok') is True)
state['status']='VERIFIED_COMPLETE_X2' if final_pass and recon_pass else 'EXACT_DIFF_X2_PASS_FINAL_RECEIPT_PENDING'
state['receipt_id']='RCT_20260911_DRIVE_MIRROR_FINAL_X2_001'
save(state)
raise SystemExit(0 if state['status']=='VERIFIED_COMPLETE_X2' else 7)
