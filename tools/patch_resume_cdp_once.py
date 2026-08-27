from pathlib import Path
p=Path('local-agent/bootstrap/RESUME_LOCAL_AGENT_ONCE.ps1')
s=p.read_text(encoding='utf-8')
anchor="Write-Host '[5/5] Ensuring future bootstrap loop...'"
if 'D78_CDP_DOWNLOAD_ONCE' not in s:
    if anchor not in s:
        raise SystemExit('RESUME_ANCHOR_MISSING')
    block=r'''
# D78 one-shot independent download diagnostic. This is deliberately outside the queue/Host active-lock path.
# It preserves the existing Chrome user-data and download configuration and never generates a new NotebookLM artifact.
$D78Marker=Join-Path $Root 'D78_CDP_DOWNLOAD_ONCE.attempted'
$D78Result=Join-Path $Root 'D78_CDP_DOWNLOAD_RESULT.json'
if(-not(Test-Path -LiteralPath $D78Marker)){
  $attempt=[ordered]@{ok=$false;action='D78_CDP_DOWNLOAD_ONCE';startedAt=(Get-Date).ToString('o');stdout='';exitCode=$null;error=''}
  try{
    $helper=Join-Path $Root 'RunNotebookLMExistingDownloadViaCDP.ps1'
    $helperUrl='https://raw.githubusercontent.com/8friend8ship-cloud/notebooklm-webapp-bridge/main/local-agent/governor/RunNotebookLMExistingDownloadViaCDP.ps1?hdcb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    Invoke-WebRequest -UseBasicParsing -Uri $helperUrl -OutFile $helper -TimeoutSec 30
    $out=& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $helper 2>&1 | Out-String
    $attempt.stdout=$out.Trim();$attempt.exitCode=$LASTEXITCODE;$attempt.ok=($LASTEXITCODE -eq 0)
  }catch{$attempt.error=$_.Exception.Message;$attempt.ok=$false}
  $attempt.completedAt=(Get-Date).ToString('o')
  $json=$attempt|ConvertTo-Json -Depth 30
  $json|Set-Content -LiteralPath $D78Result -Encoding UTF8
  Set-Content -LiteralPath $D78Marker -Value $attempt.completedAt -Encoding ASCII
  try{
    $centralName=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('MDBf7KSR7JWZ7JeQ7J207KCE7Yq4'))
    foreach($drv in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)){
      $rr=[string]$drv.Root;if(-not $rr){continue}
      foreach($cand in @((Join-Path $rr $centralName),(Join-Path $rr ('My Drive\'+$centralName)),(Join-Path $rr ('내 드라이브\'+$centralName)),(Join-Path $rr ('Google Drive\'+$centralName)))){
        if(Test-Path -LiteralPath $cand){$dest=Join-Path $cand 'Runtime_Readback';New-Item -ItemType Directory -Force -Path $dest|Out-Null;$json|Set-Content -LiteralPath (Join-Path $dest 'NOTEBOOKLM_CDP_DOWNLOAD_D78.json') -Encoding UTF8;break}
      }
    }
  }catch{}
}

'''
    s=s.replace(anchor,block+anchor,1)
p.write_text(s,encoding='utf-8')