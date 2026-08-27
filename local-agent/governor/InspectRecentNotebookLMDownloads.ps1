param([int]$Hours=48)
$ErrorActionPreference='Stop'
$downloads=Join-Path $env:USERPROFILE 'Downloads'
if(-not(Test-Path -LiteralPath $downloads)){throw 'WINDOWS_DOWNLOADS_NOT_FOUND'}
$cut=(Get-Date).AddHours(-1*[Math]::Max(1,[Math]::Min(168,$Hours)))
$exts=@('.mp3','.m4a','.wav','.ogg','.mp4','.webm','.mov','.pdf','.pptx','.xlsx','.csv','.png','.jpg','.jpeg','.webp','.docx')
$items=@(Get-ChildItem -LiteralPath $downloads -File -ErrorAction SilentlyContinue |
  Where-Object { $_.LastWriteTime -ge $cut -and $exts -contains $_.Extension.ToLowerInvariant() -and $_.Name -notlike '*.crdownload' } |
  Sort-Object LastWriteTime -Descending |
  Select-Object -First 80 |
  ForEach-Object { [ordered]@{name=$_.Name;extension=$_.Extension.ToLowerInvariant();bytes=[int64]$_.Length;lastWrite=$_.LastWriteTime.ToString('o');fullName=$_.FullName} })
[ordered]@{ok=$true;action='INSPECT_RECENT_NOTEBOOKLM_DOWNLOADS';hours=$Hours;downloads=$downloads;count=@($items).Count;items=$items;at=(Get-Date).ToString('o')} | ConvertTo-Json -Depth 8 -Compress