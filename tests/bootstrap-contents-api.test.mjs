import fs from 'node:fs';
import {execFileSync} from 'node:child_process';
const files={
  bootstrap:'local-agent/bootstrap/AgentBootstrap.ps1',
  resume:'local-agent/bootstrap/RESUME_LOCAL_AGENT_ONCE.ps1',
  auto:'local-agent/bootstrap/HomeDesignAutoResume.ps1',
  agent1166:'local-agent/releases/1.1.66/HomeDesignLocalAgent.ps1',
  stable:'local-agent/stable/agent.json'
};
const text=Object.fromEntries(Object.entries(files).map(([k,p])=>[k,fs.readFileSync(p,'utf8')]));
const must=[
 ['bootstrap contents api',text.bootstrap,'api.github.com/repos/'],
 ['bootstrap exact api sha',text.bootstrap,'Agent API blob mismatch'],
 ['resume contents api',text.resume,'api.github.com/repos/'],
 ['resume bridge via api',text.resume,"ApiContent 'runtime/stable/release.json'"],
 ['autoresume contents api',text.auto,'api.github.com/repos/'],
 ['autoresume resume sha',text.auto,'RESUME_SHA_MISMATCH'],
 ['archived agent 1166',text.agent1166,"$AgentVersion='1.1.66'"],
 ['agent bootstrap pin',text.agent1166,'321114c59e2cf0393be2c990971977fdc14ceb8c'],
 ['agent resume pin',text.agent1166,'288a157387f1ae896a7121d77b58fefe75db6cd0'],
 ['agent autoresume pin',text.agent1166,'a9ffb2f7399efc3943958d35dfcd7e01f3f1e4cb']
];
for(const [name,s,needle] of must){if(!s.includes(needle))throw new Error(`BOOTSTRAP_CONTENTS_API_STATIC_FAIL ${name}: missing ${needle}`)}
for(const [name,s] of [['bootstrap',text.bootstrap],['resume',text.resume],['auto',text.auto]]){
  if(/raw\.githubusercontent\.com\/8friend8ship-cloud\/notebooklm-webapp-bridge\/main\/local-agent\/(?:stable|releases|bootstrap)/.test(s)){
    throw new Error(`BOOTSTRAP_CONTENTS_API_STATIC_FAIL ${name}: mutable raw bootstrap/stable dependency remains`);
  }
}
const stable=JSON.parse(text.stable);
if(!/^1\.1\.\d+$/.test(String(stable.version||'')))throw new Error(`invalid stable version ${stable.version}`);
if(stable.channel!=='stable'||stable.enabled!==true)throw new Error('stable manifest channel/enabled mismatch');
const stablePath=`local-agent/releases/${stable.version}/${stable.file||'HomeDesignLocalAgent.ps1'}`;
if(!fs.existsSync(stablePath))throw new Error(`stable release file missing ${stablePath}`);
// Use the repository blob object instead of working-tree bytes. Windows checkout
// may materialize CRLF, which must not change the Git blob identity pinned by the manifest.
const blobSha=execFileSync('git',['rev-parse',`HEAD:${stablePath}`],{encoding:'utf8'}).trim().toLowerCase();
if(blobSha!==String(stable.gitBlobSha1||'').toLowerCase())throw new Error(`stable manifest SHA mismatch expected=${stable.gitBlobSha1} actual=${blobSha}`);
const stableAgent=fs.readFileSync(stablePath,'utf8');
if(!stableAgent.includes(`$AgentVersion='${stable.version}'`))throw new Error(`stable release version marker missing ${stable.version}`);
console.log(JSON.stringify({ok:true,action:'BOOTSTRAP_CONTENTS_API_STATIC',stable:stable.version,checks:must.length,noMutableRaw:true,stableBlobVerified:true}));
