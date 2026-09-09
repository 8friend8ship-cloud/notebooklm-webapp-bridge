param([string]$BeforeReopenFamily='')
$ErrorActionPreference='Continue'
$ProgressPreference='SilentlyContinue'
$Version='WINDOW_ACTIVITY_SUPERVISOR_V6_UIA_AMSI_SAFE_20260910'
$Root=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7\LocalAgent'
$StatePath=Join-Path $Root 'WINDOW_ACTIVITY_STATE.json'
$Receipt=Join-Path $Root 'WINDOW_ACTIVITY_LAST.json'
$Registry=Join-Path $Root 'RUN_OWNED_UI_REGISTRY.json'
New-Item -ItemType Directory -Force -Path $Root|Out-Null
Add-Type -AssemblyName UIAutomationClient,UIAutomationTypes -ErrorAction SilentlyContinue
Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
function Save-Json([string]$Path,$Object){try{$Object|ConvertTo-Json -Depth 50|Set-Content -LiteralPath $Path -Encoding UTF8}catch{}}
function Family-FromTitle([string]$Title){
 $naver='(?i)(NAVER|\uB124\uC774\uBC84)';$login='(?i)(login|auth|QR|account|\uB85C\uADF8\uC778|\uC778\uC99D|\uACC4\uC815)'
 if($Title-match'(?i)Desktop Commander Remote MCP|mcp\.desktopcommander\.app.*verify'){return 'REMOTE_DC_AUTH'}
 if($Title-match$naver-and$Title-match$login){return 'NAVER_AUTH'}
 if($Title-match'(?i)(NICE|niceid|i-?PIN|\uB098\uC774\uC2A4|\uBCF8\uC778)'){return 'NICE_AUTH'}
 if($Title-match'(?i)(Google Accounts|Sign in.*Google|accounts\.google|Google)'){return 'GOOGLE_AUTH'}
 if($Title-match'(?i)(Kakao|\uCE74\uCE74\uC624)'-and$Title-match$login){return 'KAKAO_AUTH'}
 return ''
}
function Expand-Registry($Node){
 $result=@();$stack=New-Object System.Collections.Stack
 foreach($n in @($Node)){$stack.Push($n)}
 while($stack.Count-gt0){
  $x=$stack.Pop();if($null-eq$x){continue}
  if($x -is [System.Array]){foreach($a in $x){$stack.Push($a)};continue}
  $names=@($x.PSObject.Properties.Name)
  if($names -contains 'runId'){$result+=,$x;continue}
  if($names -contains 'value'){foreach($a in @($x.value)){$stack.Push($a)}}
 }
 return @($result)
}
$prev=$null;try{if(Test-Path $StatePath){$prev=Get-Content $StatePath -Raw -Encoding UTF8|ConvertFrom-Json}}catch{}
$prevByKey=@{};if($prev-and$prev.windows){foreach($w in @($prev.windows)){$prevByKey[[string]$w.key]=$w}}
$rawRegistry=$null;$registryItems=@();$registryError=''
try{if(Test-Path $Registry){$rawRegistry=Get-Content $Registry -Raw -Encoding UTF8|ConvertFrom-Json;$registryItems=@(Expand-Registry $rawRegistry)}}catch{$registryError=$_.Exception.Message}
$registeredHwnd=@{};foreach($ri in $registryItems){try{if([int64]$ri.hwnd-gt0){$registeredHwnd[[string][int64]$ri.hwnd]=$ri}}catch{}}
$windows=@();$enumErrors=@();$rootElement=$null
try{$rootElement=[System.Windows.Automation.AutomationElement]::RootElement}catch{$enumErrors+=$_.Exception.Message}
if($rootElement){
 try{$tops=$rootElement.FindAll([System.Windows.Automation.TreeScope]::Children,[System.Windows.Automation.Condition]::TrueCondition)}catch{$tops=@();$enumErrors+=$_.Exception.Message}
 foreach($e in @($tops)){
  try{
   $c=$e.Current;$winPid=[int]$c.ProcessId;$hwnd=[int64]$c.NativeWindowHandle;$title=[string]$c.Name
   if($winPid-le0-or$hwnd-le0-or[string]::IsNullOrWhiteSpace($title)-or[bool]$c.IsOffscreen){continue}
   $p=Get-Process -Id $winPid -ErrorAction Stop;$r=$c.BoundingRectangle
   $key=([string]$winPid+':'+[string]$hwnd);$now=(Get-Date).ToUniversalTime().ToString('o');$first=$now;$last=$now;$unchanged=0
   if($prevByKey.ContainsKey($key)){$old=$prevByKey[$key];$first=[string]$old.firstSeenUtc;if([string]$old.title-eq$title){$unchanged=[int]$old.unchangedSamples+1;$last=[string]$old.lastChangedUtc}}
   $reg=$null;if($registeredHwnd.ContainsKey([string]$hwnd)){$reg=$registeredHwnd[[string]$hwnd]}
   $windows+=[pscustomobject][ordered]@{key=$key;pid=$winPid;hwnd=$hwnd;process=[string]$p.ProcessName;processStartUtc=$(try{$p.StartTime.ToUniversalTime().ToString('o')}catch{''});title=$title;family=(Family-FromTitle $title);left=[double]$r.Left;top=[double]$r.Top;right=[double]$r.Right;bottom=[double]$r.Bottom;foreground=$false;unchangedSamples=$unchanged;firstSeenUtc=$first;lastChangedUtc=$last;registered=[bool]($null-ne$reg);registeredState=$(if($reg){[string]$reg.state}else{''});registeredOwner=$(if($reg){[string]$reg.owner}else{''});registeredKeepOpen=$(if($reg){[bool]$reg.keepOpen}else{$false})}
  }catch{$enumErrors+=$_.Exception.Message}
 }
}
$duplicateFamilies=@($windows|Where-Object{$_.family}|Group-Object family|Where-Object{$_.Count-gt1}|ForEach-Object{$_.Name})
$nowText=(Get-Date).ToUniversalTime().ToString('s')+'Z'
$state=[ordered]@{version=$Version;timeUtc=$nowText;lastVisualCaptureUtc=$(if($prev){[string]$prev.lastVisualCaptureUtc}else{''});windows=$windows;captures=@();registryFlatCount=$registryItems.Count;nativeVisibleCount=$windows.Count;enumerationErrorCount=$enumErrors.Count};Save-Json $StatePath $state
$out=[ordered]@{ok=([string]::IsNullOrEmpty($registryError)-and$enumErrors.Count-eq0-and$windows.Count-gt0);version=$Version;time=(Get-Date).ToString('o');visualDue=$false;monitorCount=$(try{@([System.Windows.Forms.Screen]::AllScreens).Count}catch{0});captureCount=0;windowCount=$windows.Count;nativeVisibleCount=$windows.Count;enumerationErrorCount=$enumErrors.Count;enumerationErrors=@($enumErrors|Select-Object -First 20);registryRawCount=$(if($rawRegistry){@($rawRegistry).Count}else{0});registryFlatCount=$registryItems.Count;registryError=$registryError;falsePassDetected=$false;authWindowCount=@($windows|Where-Object{$_.family}).Count;duplicateFamilies=$duplicateFamilies;duplicateFamiliesRemaining=$duplicateFamilies.Count;closedSuperseded=@();closedSupersededCount=0;preReopenFamily=$BeforeReopenFamily;preReopenClosed=@();geometrySource='UIAUTOMATION_BOUNDING_RECTANGLE';activityRule='UIAUTOMATION_TOPLEVEL_VISIBLE+TITLE+PROCESS+FIRST_SEEN';closeRule='CLOSURE_DELEGATED_TO_RUN_OWNED_UI_CLEANUP';capturePolicy='DISABLED_IN_AMSI_SAFE_SUPERVISOR;SEPARATE_CAPTURE_LANE'}
Save-Json $Receipt $out;$out|ConvertTo-Json -Depth 50 -Compress;if($out.ok){exit 0}else{exit 4}
