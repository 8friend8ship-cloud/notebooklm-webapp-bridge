import fs from 'node:fs';
const files={
  bootstrap:'local-agent/bootstrap/AgentBootstrap.ps1',
  resume:'local-agent/bootstrap/RESUME_LOCAL_AGENT_ONCE.ps1',
  auto:'local-agent/bootstrap/HomeDesignAutoResume.ps1',
  agent:'local-agent/releases/1.1.66/HomeDesignLocalAgent.ps1',
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
 ['agent 1166',text.agent,"$AgentVersion='1.1.66'"],
 ['agent bootstrap pin',text.agent,'321114c59e2cf0393be2c990971977fdc14ceb8c'],
 ['agent resume pin',text.agent,'288a157387f1ae896a7121d77b58fefe75db6cd0'],
 ['agent autoresume pin',text.agent,'a9ffb2f7399efc3943958d35dfcd7e01f3f1e4cb']
];
for(const [name,s,needle] of must){if(!s.includes(needle))throw new Error(`BOOTSTRAP_CONTENTS_API_STATIC_FAIL ${name}: missing ${needle}`)}
for(const [name,s] of [['bootstrap',text.bootstrap],['resume',text.resume],['auto',text.auto]]){
  if(/raw\.githubusercontent\.com\/8friend8ship-cloud\/notebooklm-webapp-bridge\/main\/local-agent\/(?:stable|releases|bootstrap)/.test(s)){
    throw new Error(`BOOTSTRAP_CONTENTS_API_STATIC_FAIL ${name}: mutable raw bootstrap/stable dependency remains`);
  }
}
const stable=JSON.parse(text.stable);
if(stable.version!=='1.1.66')throw new Error(`stable version ${stable.version}`);
if(stable.gitBlobSha1!=='60beee0e328ea9820393e0f7dd14767a62d523f6')throw new Error('stable 1.1.66 SHA mismatch');
console.log(JSON.stringify({ok:true,action:'BOOTSTRAP_CONTENTS_API_STATIC',stable:stable.version,checks:must.length,noMutableRaw:true}));
