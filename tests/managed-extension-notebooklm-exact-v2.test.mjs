import fs from 'node:fs';
const s=fs.readFileSync('local-agent/governor/ManagedExtensionAutopilotV2.ps1','utf8');
const checks=[
 ['v2 launcher','ManagedExtensionExactTargetLauncherV2.ps1'],
 ['v2 sha','6ea89f678d4716e7ed39163e6bb0634e78eb750c'],
 ['contents api','api.github.com/repos/'],
 ['notebook marker gate','inner.extensionContextActive'],
 ['target gate','inner.targetContextVerified'],
 ['input found','inner.inputFound'],
 ['input verified','inner.inputVerified'],
 ['input restored','inner.inputRestored'],
 ['normal chrome','inner.normalChromeUntouched'],
 ['marker contract','contentScriptMarkerRequired=$true']
];
for(const [name,n] of checks)if(!s.includes(n))throw new Error(`NOTEBOOKLM_EXACT_V2_FAIL ${name}`);
const notebookBranch=s.slice(s.indexOf("if($Service -eq 'NOTEBOOKLM')"));
if(!notebookBranch.includes("launcher='EXACT_TARGET_V2'"))throw new Error('NOTEBOOKLM_EXACT_V2_FAIL launcher route');
console.log(JSON.stringify({ok:true,action:'NOTEBOOKLM_AUTOPILOT_EXACT_V2_STATIC',checks:checks.length}));
