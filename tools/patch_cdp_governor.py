from pathlib import Path

p=Path('local-agent/governor/RunChromeGovernorReadback.ps1')
s=p.read_text(encoding='utf-8')
old="[switch]$InteriorAppsScriptSync,[switch]$InspectNotebookLMDownloads,[string]$CentralRelativePath=''"
new="[switch]$InteriorAppsScriptSync,[switch]$InspectNotebookLMDownloads,[switch]$DownloadExistingNotebookArtifactViaCDP,[string]$CentralRelativePath=''"
if new not in s:
    if old not in s:
        raise SystemExit('PARAM_ANCHOR_MISSING')
    s=s.replace(old,new,1)
anchor='if($InspectNotebookLMDownloads){'
block="""if($DownloadExistingNotebookArtifactViaCDP){
  try{
    $helper=Join-Path $Root 'RunNotebookLMExistingDownloadViaCDP.ps1'
    $url='https://raw.githubusercontent.com/'+$Repo+'/main/local-agent/governor/RunNotebookLMExistingDownloadViaCDP.ps1?hdcb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    $tmp=$helper+'.download'
    Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $tmp -TimeoutSec 20
    Move-Item -LiteralPath $tmp -Destination $helper -Force
    & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $helper
    $rc=$LASTEXITCODE
    if($rc -ne 0){exit $rc}
    exit 0
  }catch{
    [ordered]@{ok=$false;action='NOTEBOOKLM_EXISTING_DOWNLOAD_CDP_TRUSTED_CLICK';error=$_.Exception.Message;at=(Get-Date).ToString('o')}|ConvertTo-Json -Compress
    exit 2
  }
}

"""
if 'if($DownloadExistingNotebookArtifactViaCDP){' not in s:
    if anchor not in s:
        raise SystemExit('INSPECT_ANCHOR_MISSING')
    s=s.replace(anchor,block+anchor,1)
p.write_text(s,encoding='utf-8')