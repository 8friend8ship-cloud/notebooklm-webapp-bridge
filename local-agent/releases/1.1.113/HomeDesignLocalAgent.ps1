param()
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
$Version='1.1.113'
$Repo='8friend8ship-cloud/notebooklm-webapp-bridge'
$Root=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7\LocalAgent'
$Inner=Join-Path $Root 'Agent1.1.112.fixed.runtime.ps1'
$InnerResult=Join-Path $Root 'AGENT_1.1.112_CHAT_PROMPT_SUBMIT_ONCE_RESULT.json'
$ValidPromptB64='7IiY7KeR65CcIOyGjOyKpOulvCDrsJTtg5XsnLzroZwgQUkg7L2Y7YWQ7LigIOyDneyCsCDsm4ztgaztlIzroZzsmrDsl5DshJwg7JuQ7J6Q66OMIOyImOynkSwg7ZW17IusIO2MqO2EtCDrtoTshJ0sIOyerOyCrOyaqSDqsIDriqXtlZwg7YWc7ZSM66a/7ZmULCDsi6TsoJwg7IKs7Jqp7J6QIOqwgOy5mCDqsoDspp3snZgg7Z2Q66aE7J2EIO2VnOq1reyWtOuhnCDrqoXtmZXtlZjqsowg7KCV66as7ZW0IOyjvOyEuOyalC4g7ZW17IusIOq3vOqxsOyZgCDsi6TsoIQg7KCB7JqpIOyInOyEnOulvCDtlajqu5gg7KCV66as7ZWY6rOgLCDsnbQg64K07Jqp7J2EIOuwlO2DleycvOuhnCBBSSDsmKTrlJTsmKQg7Jik67KE67ew66W8IOunjOuTpCDsiJgg7J6I6rKMIOykgOu5hO2VtCDso7zshLjsmpQuIOqzoOycoCDrp4jsu6Q6IE5MTV9GUkVTSF9BTExfMjAyNjA4MjlfMTkxNS4='
New-Item -ItemType Directory -Force -Path $Root|Out-Null
function FindCentral{$target=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('MDBf7KSR7JWZ7JeQ7J207KCE7Yq4'));$my=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('64K0IOuTnOudvOydtOu4jA=='));foreach($d in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)){$r=[string]$d.Root;if(-not$r){continue};foreach($c in @((Join-Path $r $target),(Join-Path $r ($my+'\'+$target)),(Join-Path $r ('My Drive\'+$target)),(Join-Path $r ('Google Drive\'+$target)))){if(Test-Path -LiteralPath $c -PathType Container){return $c}}};return ''}
function SaveCentral([string]$Name,$Object){try{$j=$Object|ConvertTo-Json -Depth 70;$j|Set-Content -LiteralPath (Join-Path $Root $Name) -Encoding UTF8;$c=FindCentral;if($c){$d=Join-Path $c 'Runtime_Readback';New-Item -ItemType Directory -Force -Path $d|Out-Null;$j|Set-Content -LiteralPath (Join-Path $d $Name) -Encoding UTF8}}catch{}}
$result=[ordered]@{ok=$false;action='AGENT_1.1.113_CHAT_PROMPT_BASE64_FIX_WRAPPER';version=$Version;startedAt=(Get-Date).ToString('o');innerFetched=$false;base64Patched=$false;innerParsed=$false;innerExit=$null;chatSubmitted=$false;innerResult=$null;normalChromeTouched=$false;bridgeChanged=$false;oauthChanged=$false;scopeChanged=$false;stage='START';error=''}
try{
 $result.stage='FETCH_INNER';$u='https://raw.githubusercontent.com/'+$Repo+'/main/local-agent/releases/1.1.112/HomeDesignLocalAgent.ps1?cb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds();Invoke-WebRequest -UseBasicParsing -Uri $u -OutFile $Inner -TimeoutSec 30;$result.innerFetched=$true
 $s=Get-Content -LiteralPath $Inner -Raw -Encoding UTF8;$patched=[regex]::Replace($s,"(?m)^\$PromptB64='[^']*'",("`$PromptB64='"+$ValidPromptB64+"'"),1);if($patched-eq$s){throw 'PROMPT_B64_PATCH_ANCHOR_NOT_FOUND'};[IO.File]::WriteAllText($Inner,$patched,(New-Object Text.UTF8Encoding($true)));$result.base64Patched=$true
 $tok=$null;$pe=$null;[void][Management.Automation.Language.Parser]::ParseFile($Inner,[ref]$tok,[ref]$pe);if($pe.Count){throw ('INNER_PARSE_FAIL '+(($pe|ForEach-Object{$_.Message})-join' | '))};$result.innerParsed=$true
 $out=& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $Inner 2>&1|Out-String;$result.innerExit=[int]$LASTEXITCODE
 if(Test-Path -LiteralPath $InnerResult){$ir=Get-Content -LiteralPath $InnerResult -Raw -Encoding UTF8|ConvertFrom-Json;$result.innerResult=$ir;$result.chatSubmitted=[bool]$ir.chatSubmitted;$result.ok=([bool]$ir.ok -and $result.chatSubmitted -and $result.innerExit-eq0)}else{throw ('INNER_RESULT_NOT_FOUND '+$out.Trim())}
 if(-not$result.ok){throw ('INNER_CHAT_FAILED '+$out.Trim())};$result.stage='DONE'
}catch{$result.error=$_.Exception.Message}
finally{$result.completedAt=(Get-Date).ToString('o');SaveCentral 'AGENT_1.1.113_CHAT_PROMPT_BASE64_FIX_WRAPPER_RESULT.json' $result}
$result|ConvertTo-Json -Depth 70 -Compress
if($result.ok){exit 0}else{exit 2}
