param(
  [string]$Title='2026-08-31 ContentOS Workflow Studio E2E',
  [string]$Marker='NLM_WORKFLOW_STUDIO_ALL_20260831_1446',
  [int]$RemoteDebuggingPort=9223,
  [int]$TimeoutSeconds=1800
)
$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$Repo='8friend8ship-cloud/notebooklm-webapp-bridge'
$Root=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7\LocalAgent'
$Receipt='AGENT_1.1.129_FRESH_ALL_STUDIO_E2E_RESULT.json'
$MarkerPath=Join-Path $Root $Receipt
New-Item -ItemType Directory -Force -Path $Root|Out-Null
function FindCentral{$target=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('MDBf7KSR7JWZ7JeQ7J207KCE7Yq4'));$my=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('64K0IOuTnOudvOydtOu4jA=='));foreach($d in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)){$r=[string]$d.Root;if(-not$r){continue};foreach($c in @((Join-Path $r $target),(Join-Path $r ($my+'\'+$target)),(Join-Path $r ('My Drive\'+$target)),(Join-Path $r ('Google Drive\'+$target)))){if(Test-Path -LiteralPath $c -PathType Container){return $c}}};''}
function Save($o){$j=$o|ConvertTo-Json -Depth 80;$j|Set-Content -LiteralPath $MarkerPath -Encoding UTF8;try{$c=FindCentral;if($c){$d=Join-Path $c 'Runtime_Readback';New-Item -ItemType Directory -Force -Path $d|Out-Null;$j|Set-Content -LiteralPath (Join-Path $d $Receipt) -Encoding UTF8}}catch{}}
function Tabs{@((Invoke-WebRequest -UseBasicParsing -Uri ("http://127.0.0.1:$RemoteDebuggingPort/json/list") -TimeoutSec 3).Content|ConvertFrom-Json|Where-Object{[string]$_.type-eq'page'})}
function Recv($w,[int]$sec){$b=New-Object byte[] 65536;$m=New-Object IO.MemoryStream;$c=New-Object Threading.CancellationTokenSource;$c.CancelAfter([Math]::Max(1000,$sec*1000));try{do{$g=New-Object ArraySegment[byte] -ArgumentList @(,$b);$r=$w.ReceiveAsync($g,$c.Token).GetAwaiter().GetResult();if($r.MessageType-eq[System.Net.WebSockets.WebSocketMessageType]::Close){throw 'CDP_CLOSED'};$m.Write($b,0,$r.Count)}while(-not$r.EndOfMessage);([Text.Encoding]::UTF8.GetString($m.ToArray())|ConvertFrom-Json)}finally{$c.Dispose();$m.Dispose()}}
function Send($w,[ref]$q,[string]$method,[hashtable]$params=@{}){$q.Value++;$id=$q.Value;$j=@{id=$id;method=$method;params=$params}|ConvertTo-Json -Depth 30 -Compress;$bb=[Text.Encoding]::UTF8.GetBytes($j);$g=New-Object ArraySegment[byte] -ArgumentList @(,$bb);$c=New-Object Threading.CancellationTokenSource;$c.CancelAfter(8000);try{[void]$w.SendAsync($g,[System.Net.WebSockets.WebSocketMessageType]::Text,$true,$c.Token).GetAwaiter().GetResult()}finally{$c.Dispose()};while($true){$z=Recv $w 8;if($z.id-eq$id){if($z.error){throw('CDP_'+$method+':'+($z.error|ConvertTo-Json -Compress))};return $z.result}}}
function Eval($w,[ref]$q,[string]$e){$r=Send $w $q 'Runtime.evaluate' @{expression=$e;returnByValue=$true;awaitPromise=$true;userGesture=$true};$r.result.value}
function Connect($tab){$w=New-Object System.Net.WebSockets.ClientWebSocket;$c=New-Object Threading.CancellationTokenSource;$c.CancelAfter(8000);try{[void]$w.ConnectAsync([Uri][string]$tab.webSocketDebuggerUrl,$c.Token).GetAwaiter().GetResult()}finally{$c.Dispose()};$w}
function ClickText($w,[ref]$q,[string]$needle){$n=$needle|ConvertTo-Json -Compress;$e="(() => {const n=$n;const vis=e=>{if(!(e instanceof HTMLElement))return false;const r=e.getBoundingClientRect(),s=getComputedStyle(e);return r.width>2&&r.height>2&&s.display!=='none'&&s.visibility!=='hidden'};const all=[...document.querySelectorAll('button,[role=button],[role=tab],a,div[tabindex]')].filter(vis);const x=all.find(e=>String([e.innerText,e.textContent,e.getAttribute('aria-label'),e.getAttribute('title')].join(' ')).includes(n));if(!x)return {ok:false,sample:document.body.innerText.slice(0,1600)};x.click();return {ok:true,text:String(x.innerText||x.textContent||'').slice(0,220)}})()";Eval $w $q $e}
function Body($w,[ref]$q){[string](Eval $w $q "document.body?document.body.innerText:''")}

$source=@"
$Marker
이 노트북은 우리 중앙 운영 워크플로우의 실제 E2E 검증용 소스다.
핵심 흐름: 중앙에이전트 PRE_CHECK → Drive/History/LAST_GOOD 확인 → Queens 원자료 수집 → 검증 Seed → T1 공통 템플릿 → T2 앱별 조리 → NotebookLM/이미지/영상/음성/문서 산출 → Drive 원본 보존 → MIME/크기/hash/FILE_ID/lineage 자동분류 → Queens/Candidate → 검증 후 Seed/Asset/Template 승격 → Workflow/Workflow Map writeback → 다음 작업에서 재사용.
실패 시 FAILURE_SIGNATURE, ROOT_CAUSE, MIN_FIX, RETEST, PREVENTION, RESUME_POINT를 중앙 기록에 남기고 blind retry를 금지한다.
생성 결과물은 실제 런타임 readback 전 VERIFIED로 표시하지 않는다.
"@
$result=[ordered]@{ok=$false;action='FRESH_ALL_STUDIO_E2E';version='1.1.129';title=$Title;marker=$Marker;startedAt=(Get-Date).ToString('o');freshNotebook=$false;sourceVerified=$false;notebookUrl='';notebookId='';artifacts=@();allStarted=$false;allReady=$false;downloadAttempted=$false;driveMirrorAttempted=$false;seedWritebackExpected=$true;stage='START';error=''}
$w=$null
try{
  $v3=Join-Path $env:TEMP 'Test-NotebookLMFreshNotebookSourceCDPV3.129.ps1'
  $raw='https://raw.githubusercontent.com/'+$Repo+'/main/local-agent/diagnostics/Test-NotebookLMFreshNotebookSourceCDPV3.ps1?cb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
  $txt=(Invoke-WebRequest -UseBasicParsing -Uri $raw -TimeoutSec 30).Content
  $txt=$txt.Replace("$Marker='NLM_FRESH_ALL_20260829_1915'",('$Marker='+($Marker|ConvertTo-Json -Compress)))
  [IO.File]::WriteAllText($v3,$txt,(New-Object Text.UTF8Encoding($true)))
  $result.stage='FRESH_NOTEBOOK_SOURCE'
  $out=& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $v3 -Title $Title -SourceText $source -ExpectedOldNotebookId '69e055e5-c8d0-4e9c-8686-58cc6da35a51' -RemoteDebuggingPort $RemoteDebuggingPort -TimeoutSeconds 180 -CdpCommandTimeoutSeconds 8 2>&1|Out-String
  $p=$null;foreach($line in @($out -split "`r?`n"|Where-Object{$_.Trim()}|Select-Object -Last 100)){try{$j=$line|ConvertFrom-Json;if($j){$p=$j}}catch{}}
  if(-not$p){throw ('FRESH_RESULT_JSON_NOT_FOUND '+$out.Trim())}
  if(-not([bool]$p.ok -and [bool]$p.freshNotebook -and [bool]$p.sourceVerified)){throw ('FRESH_SOURCE_FAILED '+[string]$p.error)}
  $result.freshNotebook=$true;$result.sourceVerified=$true;$result.notebookUrl=[string]$p.notebookUrl;$result.notebookId=[string]$p.notebookId
  $tab=@(Tabs|Where-Object{[string]$_.url-eq$result.notebookUrl})|Select-Object -First 1;if(-not$tab){throw 'FRESH_EXACT_TAB_NOT_FOUND'}
  $w=Connect $tab;$q=0;[void](Send $w ([ref]$q) 'Runtime.enable' @{});[void](Send $w ([ref]$q) 'Page.bringToFront' @{})
  $s=ClickText $w ([ref]$q) '스튜디오';if(-not$s.ok){throw 'STUDIO_TAB_NOT_FOUND'};Start-Sleep -Seconds 2
  $labels=@('AI 오디오 오버뷰','슬라이드 자료','동영상 개요','마인드맵','보고서','플래시카드','퀴즈','인포그래픽','데이터 표')
  foreach($label in $labels){
    $a=[ordered]@{label=$label;selected=$false;generateClicked=$false;started=$false;ready=$false;error=''}
    try{
      $c=ClickText $w ([ref]$q) $label;if(-not$c.ok){throw 'ARTIFACT_CONTROL_NOT_FOUND'};$a.selected=$true;Start-Sleep -Milliseconds 900
      $g=ClickText $w ([ref]$q) '생성';if(-not$g.ok){
        $b=Body $w ([ref]$q);if($b -match '생성 중|시작 중|generating|creating'){$a.started=$true}else{throw 'GENERATE_CONTROL_NOT_FOUND'}
      }else{$a.generateClicked=$true;Start-Sleep -Milliseconds 900;$b=Body $w ([ref]$q);$a.started=($b -match '생성 중|시작 중|준비되면 알림|generating|creating' -or $label -in @('마인드맵','보고서','플래시카드','퀴즈','데이터 표'))}
      [void](ClickText $w ([ref]$q) '스튜디오');Start-Sleep -Milliseconds 600
    }catch{$a.error=$_.Exception.Message}
    $result.artifacts+=,$a
  }
  $result.allStarted=(@($result.artifacts|Where-Object{$_.selected -and ($_.generateClicked -or $_.started)}).Count -ge 8)
  $result.stage='POLL_READY'
  $deadline=(Get-Date).AddSeconds($TimeoutSeconds)
  do{
    Start-Sleep -Seconds 15
    $b=Body $w ([ref]$q)
    $busy=($b -match '생성 중|시작 중|generating|creating')
    $newish=($b -match '방금 전|1분 전|2분 전|3분 전|4분 전|5분 전|6분 전|7분 전|8분 전|9분 전|10분 전')
    if(-not$busy -and $newish){$result.allReady=$true;break}
  }while((Get-Date)-lt$deadline)
  $result.ok=($result.freshNotebook -and $result.sourceVerified -and $result.allStarted)
  $result.stage=if($result.allReady){'DONE_READY'}else{'DONE_STARTED_WAITING'}
}catch{$result.ok=$false;$result.stage='ERROR';$result.error=$_.Exception.Message}
finally{if($w){try{$w.Dispose()}catch{}};$result.completedAt=(Get-Date).ToString('o');Save $result}
$result|ConvertTo-Json -Depth 80 -Compress
if($result.ok){exit 0}else{exit 2}
