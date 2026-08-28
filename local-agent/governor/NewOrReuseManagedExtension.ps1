param(
  [ValidateSet('Audit','CreateOrReuse')][string]$Mode='Audit',
  [Parameter(Mandatory=$true)][string]$Service,
  [Parameter(Mandatory=$true)][string[]]$HostPatterns,
  [string]$Capability='PAGE_PROBE',
  [string]$RegistryPath='',
  [string]$OutputRoot='',
  [switch]$AllowDraftInput
)
$ErrorActionPreference='Stop'
$Version='CENTRAL_MANAGED_EXTENSION_FACTORY_V1_20260828'
$Base=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7'
if(-not $OutputRoot){$OutputRoot=Join-Path $Base 'GeneratedExtensions'}
if(-not $RegistryPath){$RegistryPath=Join-Path $Base 'ManagedExtensions\managed-extension-autopilot-v1.json'}
New-Item -ItemType Directory -Force -Path $OutputRoot|Out-Null

function Read-Json([string]$p){if(Test-Path -LiteralPath $p){try{return Get-Content -LiteralPath $p -Raw -Encoding UTF8|ConvertFrom-Json}catch{}};return $null}
function Slug([string]$s){$x=($s.ToLowerInvariant()-replace'[^a-z0-9]+','-').Trim('-');if(-not $x){$x='managed-bridge'};return $x}
function ExactHost([string]$h){
  if($h -eq '<all_urls>'){throw 'BROAD_HOST_PERMISSION_FORBIDDEN'}
  if($h -notmatch '^https://'){throw ('HTTPS_HOST_REQUIRED:'+ $h)}
  return $h
}
$hosts=@($HostPatterns|ForEach-Object{ExactHost $_}|Sort-Object -Unique)
$registry=Read-Json $RegistryPath
$existing=$null
if($registry -and $registry.extensions){
  $existing=@($registry.extensions)|Where-Object{
    ([string]$_.service -eq $Service) -or
    ($_.platforms -and (@($_.platforms)|Where-Object{$_ -eq $Service}).Count -gt 0)
  }|Select-Object -First 1
}
if($existing){
  [pscustomobject]@{ok=$true;version=$Version;decision='REUSE_EXISTING';service=$Service;hosts=$hosts;extension=$existing}|ConvertTo-Json -Depth 30
  exit 0
}
if($Mode -eq 'Audit'){
  [pscustomobject]@{ok=$true;version=$Version;decision='CREATE_REQUIRED';service=$Service;hosts=$hosts;capability=$Capability}|ConvertTo-Json -Depth 20
  exit 0
}
$slug=Slug $Service
$root=Join-Path $OutputRoot $slug
New-Item -ItemType Directory -Force -Path $root|Out-Null
$name='Central Managed Bridge - '+$Service
$manifest=[ordered]@{
  manifest_version=3
  name=$name
  version='0.1.0'
  description='Central Agent generated bridge. Probe/draft QA only until runtime approval gates pass.'
  permissions=@('storage')
  host_permissions=$hosts
  content_scripts=@([ordered]@{matches=$hosts;js=@('content.js');run_at='document_idle'})
}
$manifest|ConvertTo-Json -Depth 20|Set-Content -LiteralPath (Join-Path $root 'manifest.json') -Encoding UTF8
$allowDraft=[bool]$AllowDraftInput
$content=@"
(()=>{
  const VERSION='0.1.0';
  const SERVICE='$Service';
  const ALLOW_DRAFT=$(if($allowDraft){'true'}else{'false'});
  const BLOCKED=/publish|post|share|upload|submit|send|generate|게시|발행|업로드|공유/i;
  function probe(){return {ok:true,service:SERVICE,version:VERSION,url:location.href,title:document.title,ts:new Date().toISOString()};}
  chrome.runtime.onMessage.addListener((m,s,send)=>{
    if(!m||m.type!=='CENTRAL_BRIDGE') return;
    if(m.action==='PROBE'){send(probe());return true;}
    if(m.action==='DRAFT_FILL'){
      if(!ALLOW_DRAFT){send({ok:false,error:'DRAFT_DISABLED'});return true;}
      const el=document.querySelector('textarea,input[type="text"],[contenteditable="true"]');
      if(!el){send({ok:false,error:'INPUT_NOT_FOUND'});return true;}
      const before=('value' in el)?el.value:el.textContent;
      if('value' in el){el.value=String(m.text||'');el.dispatchEvent(new Event('input',{bubbles:true}));}else{el.textContent=String(m.text||'');el.dispatchEvent(new InputEvent('input',{bubbles:true,inputType:'insertText',data:String(m.text||'')}));}
      const readback=('value' in el)?el.value:el.textContent;
      if('value' in el){el.value=before;el.dispatchEvent(new Event('input',{bubbles:true}));}else{el.textContent=before;el.dispatchEvent(new InputEvent('input',{bubbles:true,inputType:'insertText',data:before}));}
      send({ok:readback===String(m.text||''),readback,restored:(('value' in el)?el.value:el.textContent)===before});return true;
    }
    if(BLOCKED.test(String(m.action||''))){send({ok:false,error:'PUBLIC_OR_HIGH_IMPACT_ACTION_BLOCKED'});return true;}
    send({ok:false,error:'UNSUPPORTED_ACTION'});return true;
  });
})();
"@
$content|Set-Content -LiteralPath (Join-Path $root 'content.js') -Encoding UTF8
$registration=[ordered]@{
  name=$name
  extensionId='READBACK_AFTER_FIRST_LOAD'
  installMode='LOCAL_GENERATED_AUTO_STAGE'
  service=$Service
  hostPermissions=$hosts
  executionMode='ProbeExact'+$(if($allowDraft){'+DraftFillReadbackRestore'}else{''})
  approval='AUTO_SAFE_NO_PUBLISH; PUBLIC_PUBLISH_USER_GATE'
  status='GENERATED_RUNTIME_STAGE_PENDING'
  generatedSourcePath=$root
  capability=$Capability
}
$registration|ConvertTo-Json -Depth 20|Set-Content -LiteralPath (Join-Path $root 'registration.json') -Encoding UTF8
[pscustomobject]@{ok=$true;version=$Version;decision='CREATED';service=$Service;sourcePath=$root;manifest=(Join-Path $root 'manifest.json');registration=(Join-Path $root 'registration.json');next='STATIC_QA->CENTRAL_REGISTRY_REGISTER->AUTOPILOT_STAGE->RUNTIME_READBACK_X2'}|ConvertTo-Json -Depth 20
