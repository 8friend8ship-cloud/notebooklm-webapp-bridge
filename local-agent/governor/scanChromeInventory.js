const fs = require('fs');
const path = require('path');

function arg(name, fallback = '') {
  const i = process.argv.indexOf(`--${name}`);
  return i >= 0 && i + 1 < process.argv.length ? process.argv[i + 1] : fallback;
}
function exists(p) { try { return !!p && fs.existsSync(p); } catch { return false; } }
function readJson(p) { try { return JSON.parse(fs.readFileSync(p, 'utf8').replace(/^\uFEFF/, '')); } catch { return null; } }
function dirs(p) { try { return fs.readdirSync(p, { withFileTypes: true }).filter(x => x.isDirectory()).map(x => x.name); } catch { return []; } }
function normalize(p) { try { return path.resolve(p).toLowerCase(); } catch { return String(p || '').toLowerCase(); } }
function manifestItem(profile, id, root, unpacked, source) {
  const manifest = readJson(path.join(root, 'manifest.json'));
  if (!manifest) return null;
  const errors = [];
  const sw = manifest?.background?.service_worker;
  if (sw && !exists(path.join(root, sw))) errors.push(`missing service_worker: ${sw}`);
  for (const spec of Array.isArray(manifest.content_scripts) ? manifest.content_scripts : []) {
    for (const js of Array.isArray(spec?.js) ? spec.js : []) {
      if (js && !exists(path.join(root, js))) errors.push(`missing content_script: ${js}`);
    }
  }
  return {
    profile, id, name: String(manifest.name || ''), version: String(manifest.version || ''),
    path: root, unpacked: !!unpacked, source, fileIntegrityOk: errors.length === 0, fileErrors: errors
  };
}
function resolveSettingPath(profileRoot, settingPath) {
  const raw = String(settingPath || '');
  if (!raw) return '';
  if (path.isAbsolute(raw)) return raw;
  return path.resolve(profileRoot, raw);
}
function scanProfile(label, profileRoot) {
  const out = [], seen = new Set();
  if (!exists(profileRoot)) return out;
  const extRoot = path.join(profileRoot, 'Extensions');
  for (const id of dirs(extRoot)) {
    const versions = dirs(path.join(extRoot, id)).sort((a,b) => b.localeCompare(a, undefined, { numeric: true, sensitivity: 'base' }));
    if (!versions.length) continue;
    const root = path.join(extRoot, id, versions[0]);
    const item = manifestItem(label, id, root, false, 'PROFILE_EXTENSIONS_DIR');
    if (item) { out.push(item); seen.add(id); }
  }
  for (const prefName of ['Preferences', 'Secure Preferences']) {
    const pref = readJson(path.join(profileRoot, prefName));
    const settings = pref?.extensions?.settings;
    if (!settings || typeof settings !== 'object') continue;
    for (const [id, setting] of Object.entries(settings)) {
      if (seen.has(id) || !setting || !setting.path) continue;
      const root = resolveSettingPath(profileRoot, setting.path);
      if (!exists(path.join(root, 'manifest.json'))) continue;
      const item = manifestItem(label, id, root, true, prefName);
      if (item) { out.push(item); seen.add(id); }
    }
  }
  return out;
}

const normalRoot = arg('normalRoot');
const dedicatedUserData = arg('dedicatedUserData');
const dedicatedExtensionRoot = arg('dedicatedExtensionRoot');
const output = arg('output');
if (!output) { console.error('missing --output'); process.exit(2); }

let inventory = [];
if (exists(normalRoot)) {
  const profiles = dirs(normalRoot).filter(n => n === 'Default' || /^Profile \d+$/i.test(n));
  for (const p of profiles) inventory.push(...scanProfile(`NORMAL_CHROME/${p}`, path.join(normalRoot, p)));
}
inventory.push(...scanProfile('HOMEDESIGN_CFT/Default', path.join(dedicatedUserData, 'Default')));
if (exists(path.join(dedicatedExtensionRoot, 'manifest.json'))) {
  const target = normalize(dedicatedExtensionRoot);
  if (!inventory.some(x => normalize(x.path) === target)) {
    const item = manifestItem('HOMEDESIGN_CFT/LoadedExtension', 'RESOLVE_FROM_PROFILE', dedicatedExtensionRoot, true, 'LOCAL_AGENT_EXTENSION_ROOT');
    if (item) inventory.push(item);
  }
}
const tmp = `${output}.tmp`;
fs.mkdirSync(path.dirname(output), { recursive: true });
fs.writeFileSync(tmp, JSON.stringify(inventory, null, 2), 'utf8');
fs.renameSync(tmp, output);
console.log(JSON.stringify({ ok: true, count: inventory.length, output }));
