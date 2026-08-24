const fs = require('fs');
const path = require('path');

function arg(name, fallback = '') { const i = process.argv.indexOf(`--${name}`); return i >= 0 && i + 1 < process.argv.length ? process.argv[i + 1] : fallback; }
function exists(p) { try { return !!p && fs.existsSync(p); } catch { return false; } }
function readJson(p) { try { return JSON.parse(fs.readFileSync(p, 'utf8').replace(/^\uFEFF/, '')); } catch { return null; } }
function dirs(p) { try { return fs.readdirSync(p, { withFileTypes: true }).filter(x => x.isDirectory()).map(x => x.name); } catch { return []; } }
function normalize(p) { try { return path.resolve(p).toLowerCase(); } catch { return String(p || '').toLowerCase(); } }
function atomicJson(p, obj) { fs.mkdirSync(path.dirname(p), { recursive: true }); const t = `${p}.tmp`; fs.writeFileSync(t, JSON.stringify(obj, null, 2), 'utf8'); fs.renameSync(t, p); }
function manifestItem(profile, id, root, unpacked, source) {
  const manifest = readJson(path.join(root, 'manifest.json')); if (!manifest) return null;
  const errors = []; const sw = manifest?.background?.service_worker;
  if (sw && !exists(path.join(root, sw))) errors.push(`missing service_worker: ${sw}`);
  for (const spec of Array.isArray(manifest.content_scripts) ? manifest.content_scripts : []) for (const js of Array.isArray(spec?.js) ? spec.js : []) if (js && !exists(path.join(root, js))) errors.push(`missing content_script: ${js}`);
  return { profile, id, name: String(manifest.name || ''), version: String(manifest.version || ''), path: root, unpacked: !!unpacked, source, fileIntegrityOk: errors.length === 0, fileErrors: errors };
}
function resolveSettingPath(profileRoot, settingPath) { const raw = String(settingPath || ''); if (!raw) return ''; return path.isAbsolute(raw) ? raw : path.resolve(profileRoot, raw); }
function scanProfile(label, profileRoot) {
  const out = [], seen = new Set(); if (!exists(profileRoot)) return out;
  const extRoot = path.join(profileRoot, 'Extensions');
  for (const id of dirs(extRoot)) {
    const versions = dirs(path.join(extRoot, id)).sort((a,b) => b.localeCompare(a, undefined, { numeric: true, sensitivity: 'base' })); if (!versions.length) continue;
    const item = manifestItem(label, id, path.join(extRoot, id, versions[0]), false, 'PROFILE_EXTENSIONS_DIR'); if (item) { out.push(item); seen.add(id); }
  }
  for (const prefName of ['Preferences', 'Secure Preferences']) {
    const settings = readJson(path.join(profileRoot, prefName))?.extensions?.settings; if (!settings || typeof settings !== 'object') continue;
    for (const [id, setting] of Object.entries(settings)) {
      if (seen.has(id) || !setting?.path) continue; const root = resolveSettingPath(profileRoot, setting.path); if (!exists(path.join(root, 'manifest.json'))) continue;
      const item = manifestItem(label, id, root, true, prefName); if (item) { out.push(item); seen.add(id); }
    }
  }
  return out;
}
function scanInventory(normalRoot, dedicatedUserData, dedicatedExtensionRoot) {
  const inventory = [];
  if (exists(normalRoot)) for (const p of dirs(normalRoot).filter(n => n === 'Default' || /^Profile \d+$/i.test(n))) inventory.push(...scanProfile(`NORMAL_CHROME/${p}`, path.join(normalRoot, p)));
  inventory.push(...scanProfile('HOMEDESIGN_CFT/Default', path.join(dedicatedUserData, 'Default')));
  if (exists(path.join(dedicatedExtensionRoot, 'manifest.json')) && !inventory.some(x => normalize(x.path) === normalize(dedicatedExtensionRoot))) {
    const item = manifestItem('HOMEDESIGN_CFT/LoadedExtension', 'RESOLVE_FROM_PROFILE', dedicatedExtensionRoot, true, 'LOCAL_AGENT_EXTENSION_ROOT'); if (item) inventory.push(item);
  }
  return inventory;
}
function classify(inventory, policy) {
  const managed = Array.isArray(policy?.managedExtensions) ? policy.managedExtensions : [];
  const security = new Set(Array.isArray(policy?.securityHoldNames) ? policy.securityHoldNames : []);
  const observe = new Set(Array.isArray(policy?.observeOnlyNames) ? policy.observeOnlyNames : []);
  return inventory.map(item => {
    const rule = managed.find(x => String(x.name || '') === String(item.name || ''));
    let classification='UNREGISTERED_OBSERVE_ONLY', mode='OBSERVE_ONLY', expectedVersion='', action='OBSERVE_ONLY';
    if (rule) {
      classification='CENTRAL_MANAGED'; mode=String(rule.mode||''); expectedVersion=String(rule.canonicalVersion||'');
      if (!item.fileIntegrityOk) action='REPAIR_FILES_REQUIRED';
      else if (mode === 'LOCAL_AGENT_STABLE') action='OWNED_BY_LOCAL_AGENT';
      else if (expectedVersion && String(item.version) !== expectedVersion) action='VERSION_DIFF_HOLD_OR_CANONICAL_UPDATE';
      else action='CHECK_OK';
    } else if (security.has(String(item.name))) { classification='SECURITY_HOLD'; mode='HOLD_NO_DELETE'; action='USER_REVIEW_REQUIRED_NO_AUTO_DELETE'; }
    else if (observe.has(String(item.name))) { classification='THIRD_PARTY_OBSERVE_ONLY'; mode='OBSERVE_ONLY'; action='NO_AUTO_CHANGE'; }
    else if (item.unpacked) { classification='UNPACKED_UNREGISTERED_HOLD'; mode='HOLD_NO_DELETE'; action='REGISTER_SOURCE_BEFORE_UPDATE'; }
    return { profile:item.profile, id:item.id, name:item.name, installedVersion:item.version, expectedVersion, classification, mode, action, fileIntegrityOk:!!item.fileIntegrityOk, path:item.path, unpacked:!!item.unpacked, source:item.source, fileErrors:item.fileErrors||[] };
  });
}
function duplicates(items) {
  const m = new Map(); for (const x of items) { if (!x.name) continue; const a=m.get(x.name)||[]; a.push(x); m.set(x.name,a); }
  return [...m.entries()].filter(([,a])=>a.length>1).map(([name,a])=>({name,count:a.length,items:a.map(x=>({profile:x.profile,id:x.id,installedVersion:x.installedVersion,path:x.path}))}));
}

try {
  const normalRoot=arg('normalRoot'), dedicatedUserData=arg('dedicatedUserData'), dedicatedExtensionRoot=arg('dedicatedExtensionRoot');
  const policy=readJson(arg('policy'))||{}, release=readJson(arg('release'))||{}, agent=readJson(arg('agentState'))||{};
  const reportPath=arg('report'), inventoryPath=arg('inventory'); if(!reportPath||!inventoryPath) throw new Error('missing output paths');
  const inventory=scanInventory(normalRoot,dedicatedUserData,dedicatedExtensionRoot); const extensions=classify(inventory,policy); const dups=duplicates(extensions);
  const managedProblems=extensions.filter(x=>x.classification==='CENTRAL_MANAGED'&&!['CHECK_OK','OWNED_BY_LOCAL_AGENT'].includes(x.action));
  const report={ ok:true, version:'CHROME_EXTENSION_GOVERNOR_NODE_FAST_V3_20260824', mode:'AGENT_5MIN_NODE_DIRECT', generatedAt:new Date().toISOString(), scanEngine:'NODE_DIRECT', scanError:'', policyUpdatedAt:String(policy.updatedAt||''), notebookLocalAgent:{agentVersion:agent.agentVersion??null,installedVersion:agent.extensionVersion??null,hostVersion:agent.commandHostVersion??null,hostHealthy:agent.hostHealthy??null,targetBridgeVersion:release.version??null}, summary:{total:extensions.length,centralManaged:extensions.filter(x=>x.classification==='CENTRAL_MANAGED').length,securityHold:extensions.filter(x=>x.classification==='SECURITY_HOLD').length,unpackedUnregistered:extensions.filter(x=>x.classification==='UNPACKED_UNREGISTERED_HOLD').length,duplicates:dups.length,managedProblems:managedProblems.length}, extensions, duplicates:dups, policy:{noDelete:true,noCredentialRead:true,noNewOAuth:true,noNormalChromeRestart:true} };
  atomicJson(inventoryPath,inventory); atomicJson(reportPath,report); console.log(JSON.stringify({ok:true,scanEngine:'NODE_DIRECT',count:inventory.length,summary:report.summary,reportPath,inventoryPath}));
} catch (e) { console.error(String(e?.stack||e)); process.exit(2); }
