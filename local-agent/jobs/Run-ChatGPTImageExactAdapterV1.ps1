param(
  [ValidateSet('Preflight','Execute')][string]$Mode='Preflight',
  [string]$TaskFile='',
  [string]$CentralRootOverride='',
  [int]$CdpPort=9224,
  [int]$TimeoutMs=360000
)
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
if(-not $CentralRootOverride){$CentralRootOverride=[string]$env:CENTRAL_AGENT_ROOT}
if(-not $CentralRootOverride){throw 'CENTRAL_ROOT_REQUIRED'}
$adapter=Join-Path $PSScriptRoot '..\governor\chatgpt-image-auto-exact-adapter-v1.mjs'
if(-not(Test-Path -LiteralPath $adapter -PathType Leaf)){throw 'EXACT_ADAPTER_SCRIPT_MISSING'}
if($Mode -eq 'Execute' -and -not(Test-Path -LiteralPath $TaskFile -PathType Leaf)){throw 'EXECUTE_TASK_FILE_MISSING'}
if(-not(Test-Path -LiteralPath $CentralRootOverride -PathType Container)){throw 'CENTRAL_ROOT_UNAVAILABLE'}
$runtimeDir=Join-Path $CentralRootOverride 'Runtime_Readback\CHROME'
New-Item -ItemType Directory -Force -Path $runtimeDir|Out-Null
$args=@($adapter,'--mode',$Mode.ToLowerInvariant(),'--port',[string]$CdpPort,'--timeout-ms',[string]$TimeoutMs)
if($TaskFile){$args+=@('--task-file',$TaskFile)}
$raw=& node @args 2>&1
$exit=$LASTEXITCODE
$text=($raw|ForEach-Object{[string]$_}) -join "`n"
try{$obj=$text|ConvertFrom-Json}catch{throw "ADAPTER_JSON_INVALID:$text"}
$taskId=if($obj.taskId){[string]$obj.taskId}else{'PREFLIGHT'}
$receipt=Join-Path $runtimeDir ("CHATGPT_IMAGE_EXACT_ADAPTER_V1_{0}.json" -f ($taskId -replace '[^A-Za-z0-9._-]','_'))
$out=[ordered]@{ok=$false;mode=$Mode;taskId=$taskId;adapterExitCode=$exit;adapter=$obj;sourcePath='';driveCopyPath='';bytes=0;sha256='';mimeByExtension='';copiedToCentralDrive=$false;genericDownloadsScan=$false;newOAuth=$false;newTrigger=$false;extensionMutated=$false;generatedAt=(Get-Date).ToString('o')}
if($exit -ne 0 -or -not $obj.ok){$out.status='ADAPTER_FAILED_FAILCLOSED';$out|ConvertTo-Json -Depth 30|Set-Content -LiteralPath $receipt -Encoding UTF8;Write-Output ($out|ConvertTo-Json -Depth 30 -Compress);exit 2}
if($Mode -eq 'Preflight'){$out.ok=$true;$out.status='PREFLIGHT_PASS';$out|ConvertTo-Json -Depth 30|Set-Content -LiteralPath $receipt -Encoding UTF8;Write-Output ($out|ConvertTo-Json -Depth 30 -Compress);exit 0}
$src=[string]$obj.download.filename
if(-not $src -or -not(Test-Path -LiteralPath $src -PathType Leaf)){throw 'ADAPTER_EXACT_DOWNLOAD_FILE_MISSING'}
$item=Get-Item -LiteralPath $src
if($item.Length -le 0){throw 'ADAPTER_EXACT_DOWNLOAD_ZERO_BYTE'}
$ext=[IO.Path]::GetExtension($item.Name).ToLowerInvariant()
if($ext -notin @('.png','.jpg','.jpeg','.webp')){throw "ADAPTER_EXACT_DOWNLOAD_NOT_IMAGE:$ext"}
$sha=(Get-FileHash -LiteralPath $src -Algorithm SHA256).Hash.ToLowerInvariant()
$destDir=Join-Path $CentralRootOverride ("Runtime_Readback\IMAGE_EXECUTOR_OUTPUT\{0}" -f $taskId)
New-Item -ItemType Directory -Force -Path $destDir|Out-Null
$dest=Join-Path $destDir $item.Name
Copy-Item -LiteralPath $src -Destination $dest -Force
$destItem=Get-Item -LiteralPath $dest
$destSha=(Get-FileHash -LiteralPath $dest -Algorithm SHA256).Hash.ToLowerInvariant()
if($destItem.Length -ne $item.Length -or $destSha -ne $sha){throw 'CENTRAL_DRIVE_COPY_READBACK_MISMATCH'}
$out.ok=$true;$out.status='EXACT_IMAGE_COPIED_TO_CENTRAL_DRIVE';$out.sourcePath=$src;$out.driveCopyPath=$dest;$out.bytes=[int64]$item.Length;$out.sha256=$sha;$out.mimeByExtension=$ext;$out.copiedToCentralDrive=$true
$out|ConvertTo-Json -Depth 30|Set-Content -LiteralPath $receipt -Encoding UTF8
Write-Output ($out|ConvertTo-Json -Depth 30 -Compress)
exit 0
