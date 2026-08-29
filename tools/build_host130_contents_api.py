from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
src = ROOT / 'local-agent/releases/1.2.9/HomeDesignLocalCommandHost.final.ps1'
out = ROOT / 'local-agent/releases/1.3.0/HomeDesignLocalCommandHost.final.ps1'
text = src.read_text(encoding='utf-8')
text = text.replace("$HostVersion='1.2.9'", "$HostVersion='1.3.0'", 1)
anchor = "function Safe-TaskId([string]$TaskId){if($TaskId -notmatch '^[A-Za-z0-9_.-]{1,180}$'){throw 'unsafe taskId'};return $TaskId}\n"
helper = anchor + "function GitBlobSha1([string]$Path){$b=[IO.File]::ReadAllBytes($Path);$h=[Text.Encoding]::ASCII.GetBytes(('blob '+$b.Length+[char]0));$a=New-Object byte[]($h.Length+$b.Length);[Buffer]::BlockCopy($h,0,$a,0,$h.Length);[Buffer]::BlockCopy($b,0,$a,$h.Length,$b.Length);$s=[Security.Cryptography.SHA1]::Create();try{return (($s.ComputeHash($a)|ForEach-Object{$_.ToString('x2')})-join '')}finally{$s.Dispose()}}\n"
if anchor not in text:
    raise SystemExit('Safe-TaskId anchor missing')
text = text.replace(anchor, helper, 1)
old = "$rawUrl=\"https://raw.githubusercontent.com/$($rule.repo)/$($rule.branch)/$safeScript\";$localScript=Join-Path $taskDir ([IO.Path]::GetFileName($safeScript));Invoke-WebRequest -UseBasicParsing -Uri ($rawUrl+'?hdcb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()) -OutFile $localScript -TimeoutSec 8"
new = "$apiUrl='https://api.github.com/repos/'+[string]$rule.repo+'/contents/'+$safeScript+'?ref='+[Uri]::EscapeDataString([string]$rule.branch)+'&cb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds();$headers=@{'User-Agent'='HomeDesign-Local-Command-Host';'Accept'='application/vnd.github+json'};$resp=Invoke-RestMethod -Uri $apiUrl -Headers $headers -Method Get -TimeoutSec 15;if(-not $resp.content){throw 'SCRIPT_CONTENTS_API_EMPTY'};$localScript=Join-Path $taskDir ([IO.Path]::GetFileName($safeScript));[IO.File]::WriteAllBytes($localScript,[Convert]::FromBase64String(([string]$resp.content -replace '\\s','')));$apiSha=([string]$resp.sha).ToLowerInvariant();$localSha=(GitBlobSha1 $localScript).ToLowerInvariant();if(-not $apiSha -or $apiSha -ne $localSha){Remove-Item -LiteralPath $localScript -Force -ErrorAction SilentlyContinue;throw ('SCRIPT_CONTENTS_API_SHA_MISMATCH api='+$apiSha+' local='+$localSha)}"
if old not in text:
    raise SystemExit('raw download anchor missing')
text = text.replace(old, new, 1)
out.parent.mkdir(parents=True, exist_ok=True)
out.write_text(text, encoding='utf-8')
print(out)
