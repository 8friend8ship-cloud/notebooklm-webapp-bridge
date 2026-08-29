param(
  [Parameter(Mandatory=$true)][ValidatePattern('^[A-Za-z0-9_.-]{1,180}$')][string]$TaskId,
  [ValidateSet('AUTO','TEXT','IMAGE','AUDIO','VIDEO')][string]$TaskKind='AUTO',
  [int]$ExpectedMediaSeconds=0,
  [int]$ClaimedAgeSeconds=0,
  [int]$StartGraceSeconds=60,
  [string]$ExpectedOutputPath='',
  [int]$HostPort=8765,
  [switch]$WriteCentralReadback,
  [switch]$CreateLocalSaveSmoke,
  [switch]$SetupCaptureBridgeAutoSync,
  [switch]$KickAgent1141HostRepair,
  [switch]$KickAgent1155HostRepair
)

$ErrorActionPreference='Continue'
$ProgressPreference='SilentlyContinue'
$Base=Join-Path $env:LOCALAPPDATA 'HomeDesignAutomationV7'
$Root=Join-Path $Base 'LocalAgent'
$ResultRoot=Join-Path $Root 'CommandResults'
$TaskRoot=Join-Path $ResultRoot $TaskId
$StatusPath=Join-Path $TaskRoot 'status.json'
$ResultPath=Join-Path $TaskRoot 'result.json'

function GitBlobSha1([string]$Path){$b=[IO.File]::ReadAllBytes($Path);$h=[Text.Encoding]::ASCII.GetBytes(('blob '+$b.Length+[char]0));$a=New-Object byte[]($h.Length+$b.Length);[Buffer]::BlockCopy($h,0,$a,0,$h.Length);[Buffer]::BlockCopy($b,0,$a,$h.Length,$b.Length);$s=[Security.Cryptography.SHA1]::Create();try{return (($s.ComputeHash($a)|ForEach-Object{$_.ToString('x2')})-join '')}finally{$s.Dispose()}}
function Find-CentralRoot {
  $target=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('MDBf7KSR7JWZ7JeQ7J207KCE7Yq4'))
  foreach($drive in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)){
    $r=[string]$drive.Root;if(-not $r){continue}
    foreach($candidate in @((Join-Path $r $target),(Join-Path $r ('My Drive\'+$target)),(Join-Path $r ('내 드라이브\'+$target)),(Join-Path $r ('Google Drive\'+$target)))){if(Test-Path -LiteralPath $candidate){return $candidate}}
  }
  return ''
}

if($KickAgent1155HostRepair){
  try{
    New-Item -ItemType Directory -Force -Path $Root|Out-Null
    $canonical=Join-Path $Root 'HomeDesignLocalCommandHost.ps1'
    $tmp=$canonical+'.embedded129'
    $payload='cGFyYW0oKQokRXJyb3JBY3Rpb25QcmVmZXJlbmNlPSdTdG9wJwokUHJvZ3Jlc3NQcmVmZXJlbmNlPSdTaWxlbnRseUNvbnRpbnVlJwoKJEhvc3RWZXJzaW9uPScxLjIuOScKJFJvb3Q9Sm9pbi1QYXRoICRlbnY6TE9DQUxBUFBEQVRBICdIb21lRGVzaWduQXV0b21hdGlvblY3XExvY2FsQWdlbnQnCiRMb2dSb290PUpvaW4tUGF0aCAkUm9vdCAnTG9ncycKJFJlc3VsdFJvb3Q9Sm9pbi1QYXRoICRSb290ICdDb21tYW5kUmVzdWx0cycKJFdyYXBwZXJGaWxlPUpvaW4tUGF0aCAkUm9vdCAnSG9tZURlc2lnbkFzeW5jSm9iV3JhcHBlci5wczEnCk5ldy1JdGVtIC1JdGVtVHlwZSBEaXJlY3RvcnkgLUZvcmNlIC1QYXRoICRMb2dSb290LCRSZXN1bHRSb290fE91dC1OdWxsCiRMb2dGaWxlPUpvaW4tUGF0aCAkTG9nUm9vdCAoJ2NvbW1hbmRfaG9zdF8nKyhHZXQtRGF0ZSAtRm9ybWF0ICd5eXl5TU1kZCcpKycubG9nJykKCmZ1bmN0aW9uIExvZyhbc3RyaW5nXSRNZXNzYWdlKXtBZGQtQ29udGVudCAtTGl0ZXJhbFBhdGggJExvZ0ZpbGUgLVZhbHVlICJbJChHZXQtRGF0ZSAtRm9ybWF0ICd5eXl5LU1NLWRkIEhIOm1tOnNzJyldICRNZXNzYWdlIiAtRW5jb2RpbmcgVVRGOH0KZnVuY3Rpb24gS2lsbC1UcmVlKFtpbnRdJFByb2Nlc3NJZCl7dHJ5eyYgdGFza2tpbGwuZXhlIC9QSUQgJFByb2Nlc3NJZCAvVCAvRiAyPiRudWxsfE91dC1OdWxsfWNhdGNoe3RyeXtTdG9wLVByb2Nlc3MgLUlkICRQcm9jZXNzSWQgLUZvcmNlIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlfWNhdGNoe319fQpmdW5jdGlvbiBRdW90ZS1BcmdzKFtvYmplY3RbXV0kSXRlbXMpe3JldHVybiAoKCRJdGVtc3xGb3JFYWNoLU9iamVjdHskcz1bc3RyaW5nXSRfO2lmKCRzIC1tYXRjaCAnW1xzIl0nKXsnIicrKCRzIC1yZXBsYWNlICciJywnXCInKSsnIid9ZWxzZXskc319KS1qb2luICcgJyl9CmZ1bmN0aW9uIFdyaXRlLUpzb25BdG9taWMoW3N0cmluZ10kUGF0aCwkT2JqZWN0KXskdG1wPSRQYXRoKycudG1wJzskT2JqZWN0fENvbnZlcnRUby1Kc29uIC1EZXB0aCAzMHxTZXQtQ29udGVudCAtTGl0ZXJhbFBhdGggJHRtcCAtRW5jb2RpbmcgVVRGODtNb3ZlLUl0ZW0gLUxpdGVyYWxQYXRoICR0bXAgLURlc3RpbmF0aW9uICRQYXRoIC1Gb3JjZX0KZnVuY3Rpb24gUmVhZC1Kc29uKFtzdHJpbmddJFBhdGgpe2lmKC1ub3QoVGVzdC1QYXRoIC1MaXRlcmFsUGF0aCAkUGF0aCkpe3JldHVybiAkbnVsbH07dHJ5e3JldHVybiBHZXQtQ29udGVudCAtTGl0ZXJhbFBhdGggJFBhdGggLVJhdyAtRW5jb2RpbmcgVVRGOHxDb252ZXJ0RnJvbS1Kc29ufWNhdGNoe3JldHVybiAkbnVsbH19CmZ1bmN0aW9uIEdldC1WYWx1ZSgkT2JqZWN0LFtzdHJpbmdbXV0kTmFtZXMpe2lmKC1ub3QgJE9iamVjdCl7cmV0dXJuICRudWxsfTtmb3JlYWNoKCRuYW1lIGluICROYW1lcyl7JHByb3A9JE9iamVjdC5QU09iamVjdC5Qcm9wZXJ0aWVzWyRuYW1lXTtpZigkcHJvcCAtYW5kICRudWxsIC1uZSAkcHJvcC5WYWx1ZSAtYW5kIFtzdHJpbmddJHByb3AuVmFsdWUgLW5lICcnKXtyZXR1cm4gJHByb3AuVmFsdWV9fTtyZXR1cm4gJG51bGx9CmZ1bmN0aW9uIFNhZmUtVGFza0lkKFtzdHJpbmddJFRhc2tJZCl7aWYoJFRhc2tJZCAtbm90bWF0Y2ggJ15bQS1aYS16MC05Xy4tXXsxLDE4MH0kJyl7dGhyb3cgJ3Vuc2FmZSB0YXNrSWQnfTtyZXR1cm4gJFRhc2tJZH0KCiR3cmFwcGVyPUAnCnBhcmFtKAogIFtQYXJhbWV0ZXIoTWFuZGF0b3J5PSR0cnVlKV1bc3RyaW5nXSRTY3JpcHRQYXRoLAogIFtQYXJhbWV0ZXIoTWFuZGF0b3J5PSR0cnVlKV1bc3RyaW5nXSRBcmdzUGF0aCwKICBbUGFyYW1ldGVyKE1hbmRhdG9yeT0kdHJ1ZSldW3N0cmluZ10kUmVzdWx0UGF0aCwKICBbaW50XSRUaW1lb3V0U2Vjb25kcz02MDAKKQokRXJyb3JBY3Rpb25QcmVmZXJlbmNlPSdDb250aW51ZScKaWYoJFRpbWVvdXRTZWNvbmRzIC1sdCAzMCl7JFRpbWVvdXRTZWNvbmRzPTMwfTtpZigkVGltZW91dFNlY29uZHMgLWd0IDE4MDApeyRUaW1lb3V0U2Vjb25kcz0xODAwfQpmdW5jdGlvbiBRdW90ZS1BcmdzKFtvYmplY3RbXV0kSXRlbXMpe3JldHVybiAoKCRJdGVtc3xGb3JFYWNoLU9iamVjdHskcz1bc3RyaW5nXSRfO2lmKCRzIC1tYXRjaCAnW1xzIl0nKXsnIicrKCRzIC1yZXBsYWNlICciJywnXCInKSsnIid9ZWxzZXskc319KS1qb2luICcgJyl9CmZ1bmN0aW9uIEtpbGwtVHJlZShbaW50XSRQcm9jZXNzSWQpe3RyeXsmIHRhc2traWxsLmV4ZSAvUElEICRQcm9jZXNzSWQgL1QgL0YgMj4kbnVsbHxPdXQtTnVsbH1jYXRjaHt0cnl7U3RvcC1Qcm9jZXNzIC1JZCAkUHJvY2Vzc0lkIC1Gb3JjZSAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZX1jYXRjaHt9fX0KJGFyZ3NMaXN0PUAoKTtpZihUZXN0LVBhdGggLUxpdGVyYWxQYXRoICRBcmdzUGF0aCl7dHJ5eyRsb2FkZWQ9R2V0LUNvbnRlbnQgLUxpdGVyYWxQYXRoICRBcmdzUGF0aCAtUmF3IC1FbmNvZGluZyBVVEY4fENvbnZlcnRGcm9tLUpzb247aWYoJG51bGwgLW5lICRsb2FkZWQpeyRhcmdzTGlzdD1AKCRsb2FkZWQpfX1jYXRjaHt9fQokcHNpPU5ldy1PYmplY3QgRGlhZ25vc3RpY3MuUHJvY2Vzc1N0YXJ0SW5mbwokcHNpLkZpbGVOYW1lPSdwb3dlcnNoZWxsLmV4ZSc7JHBzaS5Vc2VTaGVsbEV4ZWN1dGU9JGZhbHNlOyRwc2kuUmVkaXJlY3RTdGFuZGFyZE91dHB1dD0kdHJ1ZTskcHNpLlJlZGlyZWN0U3RhbmRhcmRFcnJvcj0kdHJ1ZTskcHNpLkNyZWF0ZU5vV2luZG93PSR0cnVlCiRwc2kuQXJndW1lbnRzPVF1b3RlLUFyZ3MgKEAoJy1Ob1Byb2ZpbGUnLCctRXhlY3V0aW9uUG9saWN5JywnQnlwYXNzJywnLUZpbGUnLCRTY3JpcHRQYXRoKStAKCRhcmdzTGlzdCkpCiRwcm9jPU5ldy1PYmplY3QgRGlhZ25vc3RpY3MuUHJvY2VzczskcHJvYy5TdGFydEluZm89JHBzaTtbdm9pZF0kcHJvYy5TdGFydCgpCiRvdXRUYXNrPSRwcm9jLlN0YW5kYXJkT3V0cHV0LlJlYWRUb0VuZEFzeW5jKCk7JGVyclRhc2s9JHByb2MuU3RhbmRhcmRFcnJvci5SZWFkVG9FbmRBc3luYygpOyRmaW5pc2hlZD0kcHJvYy5XYWl0Rm9yRXhpdCgkVGltZW91dFNlY29uZHMqMTAwMCkKJHRpbWVkT3V0PSRmYWxzZQppZigtbm90ICRmaW5pc2hlZCl7JHRpbWVkT3V0PSR0cnVlOyRjaGlsZElkPSRwcm9jLklkO0tpbGwtVHJlZSAtUHJvY2Vzc0lkICRjaGlsZElkO3RyeXtbdm9pZF0kcHJvYy5XYWl0Rm9yRXhpdCg1MDAwKX1jYXRjaHt9fQokc3Rkb3V0PScnOyRzdGRlcnI9Jyc7aWYoJG91dFRhc2suSXNDb21wbGV0ZWQpe3RyeXskc3Rkb3V0PSRvdXRUYXNrLlJlc3VsdH1jYXRjaHt9fWVsc2V7JHN0ZG91dD0nW3N0ZG91dCBzdHJlYW0gZGlkIG5vdCBjbG9zZSBiZWZvcmUgdGltZW91dF0nfTtpZigkZXJyVGFzay5Jc0NvbXBsZXRlZCl7dHJ5eyRzdGRlcnI9JGVyclRhc2suUmVzdWx0fWNhdGNoe319ZWxzZXskc3RkZXJyPSdbc3RkZXJyIHN0cmVhbSBkaWQgbm90IGNsb3NlIGJlZm9yZSB0aW1lb3V0XSd9CiRleGl0Q29kZT0xMjQ7aWYoLW5vdCAkdGltZWRPdXQpe3RyeXskZXhpdENvZGU9JHByb2MuRXhpdENvZGV9Y2F0Y2h7JGV4aXRDb2RlPTF9fQokcmVzdWx0PVtvcmRlcmVkXUB7b2s9KCRleGl0Q29kZSAtZXEgMCAtYW5kIC1ub3QgJHRpbWVkT3V0KTtleGl0Q29kZT0kZXhpdENvZGU7dGltZWRPdXQ9JHRpbWVkT3V0O3RpbWVvdXRTZWNvbmRzPSRUaW1lb3V0U2Vjb25kcztzdGRvdXQ9KFtzdHJpbmddJHN0ZG91dCkuVHJpbSgpO3N0ZGVycj0oW3N0cmluZ10kc3RkZXJyKS5UcmltKCk7Y29tcGxldGVkQXQ9KEdldC1EYXRlKS5Ub1N0cmluZygnbycpfQokdG1wPSRSZXN1bHRQYXRoKycudG1wJzskcmVzdWx0fENvbnZlcnRUby1Kc29uIC1EZXB0aCAzMHxTZXQtQ29udGVudCAtTGl0ZXJhbFBhdGggJHRtcCAtRW5jb2RpbmcgVVRGODtNb3ZlLUl0ZW0gLUxpdGVyYWxQYXRoICR0bXAgLURlc3RpbmF0aW9uICRSZXN1bHRQYXRoIC1Gb3JjZQonQApTZXQtQ29udGVudCAtTGl0ZXJhbFBhdGggJFdyYXBwZXJGaWxlIC1WYWx1ZSAkd3JhcHBlciAtRW5jb2RpbmcgVVRGOAoKZnVuY3Rpb24gRmluZC1IZWFkZXJFbmQoW2J5dGVbXV0kQnl0ZXMpe2ZvcigkaT0wOyRpIC1sZSAkQnl0ZXMuTGVuZ3RoLTQ7JGkrKyl7aWYoJEJ5dGVzWyRpXS1lcSAxMyAtYW5kICRCeXRlc1skaSsxXS1lcSAxMCAtYW5kICRCeXRlc1skaSsyXS1lcSAxMyAtYW5kICRCeXRlc1skaSszXS1lcSAxMCl7cmV0dXJuICRpfX07cmV0dXJuIC0xfQpmdW5jdGlvbiBSZWFkLUh0dHBSZXF1ZXN0KFtOZXQuU29ja2V0cy5OZXR3b3JrU3RyZWFtXSRTdHJlYW0pewogICRtcz1OZXctT2JqZWN0IElPLk1lbW9yeVN0cmVhbTskYnVmPU5ldy1PYmplY3QgYnl0ZVtdIDgxOTI7JGhlYWRlckVuZD0tMQogIHdoaWxlKCRoZWFkZXJFbmQgLWx0IDApeyRuPSRTdHJlYW0uUmVhZCgkYnVmLDAsJGJ1Zi5MZW5ndGgpO2lmKCRuIC1sZSAwKXt0aHJvdyAnY2xpZW50IGNsb3NlZCBiZWZvcmUgaGVhZGVycyd9OyRtcy5Xcml0ZSgkYnVmLDAsJG4pO2lmKCRtcy5MZW5ndGggLWd0IDEwNDg1NzYpe3Rocm93ICdyZXF1ZXN0IGhlYWRlcnMgdG9vIGxhcmdlJ307JGhlYWRlckVuZD1GaW5kLUhlYWRlckVuZCAkbXMuVG9BcnJheSgpfQogICRhbGw9JG1zLlRvQXJyYXkoKTskaGVhZGVyVGV4dD1bVGV4dC5FbmNvZGluZ106OkFTQ0lJLkdldFN0cmluZygkYWxsLDAsJGhlYWRlckVuZCk7JGxpbmVzPSRoZWFkZXJUZXh0IC1zcGxpdCAiYHJgbiI7JHBhcnRzPSRsaW5lc1swXSAtc3BsaXQgJyAnO2lmKCRwYXJ0cy5Db3VudCAtbHQgMil7dGhyb3cgJ2ludmFsaWQgcmVxdWVzdCBsaW5lJ30KICAkaGVhZGVycz1Ae307aWYoJGxpbmVzLkNvdW50IC1ndCAxKXtmb3JlYWNoKCRsaW5lIGluICRsaW5lc1sxLi4oJGxpbmVzLkNvdW50LTEpXSl7aWYoJGxpbmUgLW1hdGNoICdeKFteOl0rKTpccyooLiopJCcpeyRoZWFkZXJzWyRtYXRjaGVzWzFdLlRyaW0oKS5Ub0xvd2VySW52YXJpYW50KCldPSRtYXRjaGVzWzJdLlRyaW0oKX19fQogICRjb250ZW50TGVuZ3RoPTA7aWYoJGhlYWRlcnMuQ29udGFpbnNLZXkoJ2NvbnRlbnQtbGVuZ3RoJykpe1t2b2lkXVtpbnRdOjpUcnlQYXJzZShbc3RyaW5nXSRoZWFkZXJzWydjb250ZW50LWxlbmd0aCddLFtyZWZdJGNvbnRlbnRMZW5ndGgpfTtpZigkY29udGVudExlbmd0aCAtZ3QgMTA0ODU3NjApe3Rocm93ICdyZXF1ZXN0IGJvZHkgdG9vIGxhcmdlJ30KICAkYm9keVN0YXJ0PSRoZWFkZXJFbmQrNDt3aGlsZSgoJG1zLkxlbmd0aC0kYm9keVN0YXJ0KSAtbHQgJGNvbnRlbnRMZW5ndGgpeyRuPSRTdHJlYW0uUmVhZCgkYnVmLDAsJGJ1Zi5MZW5ndGgpO2lmKCRuIC1sZSAwKXticmVha307JG1zLldyaXRlKCRidWYsMCwkbil9CiAgJGFsbD0kbXMuVG9BcnJheSgpOyRhdmFpbGFibGU9W01hdGhdOjpNYXgoMCxbTWF0aF06Ok1pbigkY29udGVudExlbmd0aCwkYWxsLkxlbmd0aC0kYm9keVN0YXJ0KSk7JGJvZHk9Jyc7aWYoJGF2YWlsYWJsZSAtZ3QgMCl7JGJvZHk9W1RleHQuRW5jb2RpbmddOjpVVEY4LkdldFN0cmluZygkYWxsLCRib2R5U3RhcnQsJGF2YWlsYWJsZSl9CiAgcmV0dXJuIFtwc2N1c3RvbW9iamVjdF1Ae21ldGhvZD1bc3RyaW5nXSRwYXJ0c1swXTtwYXRoPVtzdHJpbmddJHBhcnRzWzFdO2hlYWRlcnM9JGhlYWRlcnM7Ym9keT0kYm9keX0KfQpmdW5jdGlvbiBTZW5kLUh0dHBKc29uKFtOZXQuU29ja2V0cy5OZXR3b3JrU3RyZWFtXSRTdHJlYW0sJE9iamVjdCxbaW50XSRTdGF0dXM9MjAwKXsKICAkanNvbj0kT2JqZWN0fENvbnZlcnRUby1Kc29uIC1EZXB0aCAzMCAtQ29tcHJlc3M7JGJvZHk9W1RleHQuRW5jb2RpbmddOjpVVEY4LkdldEJ5dGVzKCRqc29uKQogICRyZWFzb249aWYoJFN0YXR1cyAtZXEgMjAwKXsnT0snfWVsc2VpZigkU3RhdHVzIC1lcSA0MDQpeydOb3QgRm91bmQnfWVsc2VpZigkU3RhdHVzIC1lcSA0MDkpeydDb25mbGljdCd9ZWxzZXsnSW50ZXJuYWwgU2VydmVyIEVycm9yJ30KICAkaGVhZD0iSFRUUC8xLjEgJFN0YXR1cyAkcmVhc29uYHJgbkNvbnRlbnQtVHlwZTogYXBwbGljYXRpb24vanNvbjsgY2hhcnNldD11dGYtOGByYG5Db250ZW50LUxlbmd0aDogJCgkYm9keS5MZW5ndGgpYHJgbkFjY2Vzcy1Db250cm9sLUFsbG93LU9yaWdpbjogKmByYG5BY2Nlc3MtQ29udHJvbC1BbGxvdy1IZWFkZXJzOiBDb250ZW50LVR5cGVgcmBuQWNjZXNzLUNvbnRyb2wtQWxsb3ctTWV0aG9kczogR0VULFBPU1QsT1BUSU9OU2ByYG5Db25uZWN0aW9uOiBjbG9zZWByYG5gcmBuIgogICRoYj1bVGV4dC5FbmNvZGluZ106OkFTQ0lJLkdldEJ5dGVzKCRoZWFkKTskU3RyZWFtLldyaXRlKCRoYiwwLCRoYi5MZW5ndGgpO2lmKCRib2R5Lkxlbmd0aCl7JFN0cmVhbS5Xcml0ZSgkYm9keSwwLCRib2R5Lkxlbmd0aCl9OyRTdHJlYW0uRmx1c2goKQp9CmZ1bmN0aW9uIFF1ZXJ5LVRhc2tJZChbc3RyaW5nXSRQYXRoKXtpZigkUGF0aCAtbWF0Y2ggJ14vcmVzdWx0XD90YXNrSWQ9KC4rKSQnKXtyZXR1cm4gW1VyaV06OlVuZXNjYXBlRGF0YVN0cmluZyhbc3RyaW5nXSRtYXRjaGVzWzFdKX07cmV0dXJuICcnfQoKJEFsbG93UnVsZXM9QCgKICBbcHNjdXN0b21vYmplY3RdQHtyZXBvPSc4ZnJpZW5kOHNoaXAtY2xvdWQvYW5pbWF0aW9uJzticmFuY2g9J2NvZGV4L3ZpZGVvLXByb21vLWFnZW50LXdvcmtmbG93LTIwMjYwODIzJztzY3JpcHRzPUAoJ3Rvb2xzL1J1bi1BbmltYXRpb25UZXN0RGVwbG95bWVudEUyRS5wczEnLCd0b29scy9SZWNvdmVyLUFuaW1hdGlvblJ1bnRpbWUtTGluZWFnZS5wczEnLCd0b29scy9SZWNvdmVyLUFuaW1hdGlvblZlcmNlbC1MaW5lYWdlLnBzMScsJ3Rvb2xzL1N5bmMtQW5pbWF0aW9uVmlkZW9BZ2VudHNUb0V4aXN0aW5nU2NyaXB0LnBzMScsJ3Rvb2xzL1JlbmRlci1WaWRlb1Byb2R1Y3Rpb25NYW5pZmVzdC5wczEnLCd0b29scy9SdW4tVmlkZW9GcmFtZVFBLnBzMScsJ3Rvb2xzL1J1bi1BZ2VudERhc2hib2FyZFByb21vUHJvZHVjdGlvbkUyRS5wczEnKX0sCiAgW3BzY3VzdG9tb2JqZWN0XUB7cmVwbz0nOGZyaWVuZDhzaGlwLWNsb3VkL25vdGVib29rbG0td2ViYXBwLWJyaWRnZSc7YnJhbmNoPSdtYWluJztzY3JpcHRzPUAoJ2xvY2FsLWFnZW50L2dvdmVybm9yL1J1bkNocm9tZUdvdmVybm9yUmVhZGJhY2sucHMxJywnbG9jYWwtYWdlbnQvZ292ZXJub3IvUnVuQ2hyb21lR292ZXJub3JSZWFkYmFja1YyLnBzMScsJ2xvY2FsLWFnZW50L2RpYWdub3N0aWNzL1Rlc3QtTm90ZWJvb2tMTUNsYWltU3RhcnRCcmlkZ2UucHMxJywnbG9jYWwtYWdlbnQvZ292ZXJub3IvSW5zcGVjdFJlY2VudE5vdGVib29rTE1Eb3dubG9hZHMucHMxJywnbG9jYWwtYWdlbnQvZ292ZXJub3IvTWlycm9yTm90ZWJvb2tMTUFydGlmYWN0VG9Ecml2ZS5wczEnLCdsb2NhbC1hZ2VudC9nb3Zlcm5vci9XYXRjaE5vdGVib29rTE1Eb3dubG9hZHNUb0NhcHR1cmVCcmlkZ2UucHMxJywnbG9jYWwtYWdlbnQvY2FwdHVyZS9NYW5hZ2VDaHJvbWVFeHRlbnNpb25BcnRpZmFjdHMucHMxJywnbG9jYWwtYWdlbnQvY2FwdHVyZS9TZXR1cC1DaHJvbWVFeHRlbnNpb25DYXB0dXJlQnJpZGdlLnBzMScsJ2xvY2FsLWFnZW50L2dvdmVybm9yL01hbmFnZWRFeHRlbnNpb25BdXRvcGlsb3RWMi5wczEnLCdsb2NhbC1hZ2VudC9nb3Zlcm5vci9NYW5hZ2VkRXh0ZW5zaW9uRXhhY3RUYXJnZXRMYXVuY2hlci5wczEnLCdsb2NhbC1hZ2VudC9nb3Zlcm5vci9SdW4tRXhhY3RUYXJnZXROb3RlYm9va0xNUmVncmVzc2lvbi5wczEnLCdsb2NhbC1hZ2VudC9nb3Zlcm5vci9TeW5jLUNlbnRyYWxMZWFybmluZ1FhQXBwc1NjcmlwdC5wczEnLCdsb2NhbC1hZ2VudC9nb3Zlcm5vci9SdW4tR2VtaW5pV2ViTGVhcm5pbmdRYS5wczEnLCdsb2NhbC1hZ2VudC9nb3Zlcm5vci9JbnNwZWN0LUZsb3dBcHByb3ZlZEFjY291bnRDcmVkaXRzLnBzMScpfSwKICBbcHNjdXN0b21vYmplY3RdQHtyZXBvPSc4ZnJpZW5kOHNoaXAtY2xvdWQvY29udGVudHMtb3MtZ2l0JzticmFuY2g9J21haW4nO3NjcmlwdHM9QCgndG9vbHMvU3dpdGNoLUNvbnRlbnRPUy1WZXJjZWxHaXQucHMxJywndG9vbHMvUmVwYWlyLUNvbnRlbnRPUy1Ecml2ZUNhY2hlQXBwc1NjcmlwdC5wczEnKX0KKQoKZnVuY3Rpb24gU3RhcnQtQXN5bmNUYXNrKCRUYXNrKXsKICAkdGFza0lkPVNhZmUtVGFza0lkIChbc3RyaW5nXShHZXQtVmFsdWUgJFRhc2sgQCgndGFza0lkJywnVEFTS19JRCcpKSk7JHRhc2tEaXI9Sm9pbi1QYXRoICRSZXN1bHRSb290ICR0YXNrSWQ7TmV3LUl0ZW0gLUl0ZW1UeXBlIERpcmVjdG9yeSAtRm9yY2UgLVBhdGggJHRhc2tEaXJ8T3V0LU51bGwKICAkcmVzdWx0UGF0aD1Kb2luLVBhdGggJHRhc2tEaXIgJ3Jlc3VsdC5qc29uJzskc3RhdHVzUGF0aD1Kb2luLVBhdGggJHRhc2tEaXIgJ3N0YXR1cy5qc29uJwogICRleGlzdGluZ1Jlc3VsdD1SZWFkLUpzb24gJHJlc3VsdFBhdGg7aWYoJGV4aXN0aW5nUmVzdWx0KXtyZXR1cm4gW29yZGVyZWRdQHtvaz0kdHJ1ZTtzdGF0ZT0nRE9ORSc7dGFza0lkPSR0YXNrSWQ7cmVzdWx0PSRleGlzdGluZ1Jlc3VsdDtob3N0VmVyc2lvbj0kSG9zdFZlcnNpb259fQogICRleGlzdGluZ1N0YXR1cz1SZWFkLUpzb24gJHN0YXR1c1BhdGg7aWYoJGV4aXN0aW5nU3RhdHVzIC1hbmQgJGV4aXN0aW5nU3RhdHVzLndyYXBwZXJQaWQpeyRwPUdldC1Qcm9jZXNzIC1JZCAoW2ludF0kZXhpc3RpbmdTdGF0dXMud3JhcHBlclBpZCkgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWU7aWYoJHApe3JldHVybiBbb3JkZXJlZF1Ae29rPSR0cnVlO3N0YXRlPSdSVU5OSU5HJzt0YXNrSWQ9JHRhc2tJZDtzdGFydGVkQXQ9JGV4aXN0aW5nU3RhdHVzLnN0YXJ0ZWRBdDtob3N0VmVyc2lvbj0kSG9zdFZlcnNpb259fX0KICAkdGFza1R5cGU9W3N0cmluZ10oR2V0LVZhbHVlICRUYXNrIEAoJ3Rhc2tUeXBlJywnVEFTS19UWVBFJykpO2lmKCR0YXNrVHlwZSAtbmUgJ0xPQ0FMX1BPV0VSU0hFTEwnKXt0aHJvdyAndGFza1R5cGUgbm90IGFsbG93ZWQnfQogICRzb3VyY2VUZXh0PVtzdHJpbmddKEdldC1WYWx1ZSAkVGFzayBAKCdzb3VyY2VUZXh0JywnU09VUkNFX1RFWFQnKSk7JHNwZWM9JHNvdXJjZVRleHR8Q29udmVydEZyb20tSnNvbgogICRydWxlPSRBbGxvd1J1bGVzfFdoZXJlLU9iamVjdHtbc3RyaW5nXSRfLnJlcG8gLWVxIFtzdHJpbmddJHNwZWMucmVwbyAtYW5kIFtzdHJpbmddJF8uYnJhbmNoIC1lcSBbc3RyaW5nXSRzcGVjLmJyYW5jaH18U2VsZWN0LU9iamVjdCAtRmlyc3QgMTtpZigtbm90ICRydWxlKXt0aHJvdyAncmVwby9icmFuY2ggbm90IGFsbG93bGlzdGVkJ30KICAkc2FmZVNjcmlwdD1bc3RyaW5nXSRzcGVjLnNjcmlwdDtpZigkc2FmZVNjcmlwdCAtbWF0Y2ggJ1wuXC4nIC1vciAkc2FmZVNjcmlwdC5TdGFydHNXaXRoKCcvJykpe3Rocm93ICd1bnNhZmUgc2NyaXB0IHBhdGgnfTtpZihAKCRydWxlLnNjcmlwdHMpIC1ub3Rjb250YWlucyAkc2FmZVNjcmlwdCl7dGhyb3cgJ3NjcmlwdCBub3QgYWxsb3dsaXN0ZWQnfQogICRyYXdVcmw9Imh0dHBzOi8vcmF3LmdpdGh1YnVzZXJjb250ZW50LmNvbS8kKCRydWxlLnJlcG8pLyQoJHJ1bGUuYnJhbmNoKS8kc2FmZVNjcmlwdCI7JGxvY2FsU2NyaXB0PUpvaW4tUGF0aCAkdGFza0RpciAoW0lPLlBhdGhdOjpHZXRGaWxlTmFtZSgkc2FmZVNjcmlwdCkpO0ludm9rZS1XZWJSZXF1ZXN0IC1Vc2VCYXNpY1BhcnNpbmcgLVVyaSAoJHJhd1VybCsnP2hkY2I9JytbRGF0ZVRpbWVPZmZzZXRdOjpVdGNOb3cuVG9Vbml4VGltZU1pbGxpc2Vjb25kcygpKSAtT3V0RmlsZSAkbG9jYWxTY3JpcHQgLVRpbWVvdXRTZWMgOAogICRhcmdzTGlzdD1AKCk7aWYoJHNwZWMuYXJncyl7Zm9yZWFjaCgkYXJnUHJvcCBpbiAkc3BlYy5hcmdzLlBTT2JqZWN0LlByb3BlcnRpZXMpeyRuYW1lPVtzdHJpbmddJGFyZ1Byb3AuTmFtZTtpZigkbmFtZSAtbm90bWF0Y2ggJ15bQS1aYS16XVtBLVphLXowLTlfXSokJyl7dGhyb3cgInVuc2FmZSBhcmcgbmFtZTogJG5hbWUifTtpZigkYXJnUHJvcC5WYWx1ZSAtaXMgW2Jvb2xdKXtpZihbYm9vbF0kYXJnUHJvcC5WYWx1ZSl7JGFyZ3NMaXN0Kz0iLSRuYW1lIn07Y29udGludWV9OyRhcmdzTGlzdCs9Ii0kbmFtZSI7JGFyZ3NMaXN0Kz1bc3RyaW5nXSRhcmdQcm9wLlZhbHVlfX0KICAkYXJnc1BhdGg9Sm9pbi1QYXRoICR0YXNrRGlyICdhcmdzLmpzb24nO0NvbnZlcnRUby1Kc29uIC1JbnB1dE9iamVjdCBAKCRhcmdzTGlzdCkgLURlcHRoIDEwfFNldC1Db250ZW50IC1MaXRlcmFsUGF0aCAkYXJnc1BhdGggLUVuY29kaW5nIFVURjgKICAkdGltZW91dD02MDA7JHJhd1RpbWVvdXQ9R2V0LVZhbHVlICRUYXNrIEAoJ3RpbWVvdXRTZWNvbmRzJywnVElNRU9VVF9TRUNPTkRTJywndGltZW91dF9zZWNvbmRzJyk7aWYoJHJhd1RpbWVvdXQpeyRwYXJzZWQ9MDtpZihbaW50XTo6VHJ5UGFyc2UoW3N0cmluZ10kcmF3VGltZW91dCxbcmVmXSRwYXJzZWQpIC1hbmQgJHBhcnNlZCAtZ3QgMCl7JHRpbWVvdXQ9JHBhcnNlZH19O2lmKCR0aW1lb3V0IC1sdCAzMCl7JHRpbWVvdXQ9MzB9O2lmKCR0aW1lb3V0IC1ndCAxODAwKXskdGltZW91dD0xODAwfQogIFJlbW92ZS1JdGVtIC1MaXRlcmFsUGF0aCAkcmVzdWx0UGF0aCAtRm9yY2UgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUKICAkcHNpPU5ldy1PYmplY3QgRGlhZ25vc3RpY3MuUHJvY2Vzc1N0YXJ0SW5mbzskcHNpLkZpbGVOYW1lPSdwb3dlcnNoZWxsLmV4ZSc7JHBzaS5Vc2VTaGVsbEV4ZWN1dGU9JGZhbHNlOyRwc2kuQ3JlYXRlTm9XaW5kb3c9JHRydWUKICAkcHNpLkFyZ3VtZW50cz1RdW90ZS1BcmdzIEAoJy1Ob1Byb2ZpbGUnLCctRXhlY3V0aW9uUG9saWN5JywnQnlwYXNzJywnLUZpbGUnLCRXcmFwcGVyRmlsZSwnLVNjcmlwdFBhdGgnLCRsb2NhbFNjcmlwdCwnLUFyZ3NQYXRoJywkYXJnc1BhdGgsJy1SZXN1bHRQYXRoJywkcmVzdWx0UGF0aCwnLVRpbWVvdXRTZWNvbmRzJyxbc3RyaW5nXSR0aW1lb3V0KQogICR3cmFwcGVyUHJvYz1bRGlhZ25vc3RpY3MuUHJvY2Vzc106OlN0YXJ0KCRwc2kpOyRzdGF0dXM9W29yZGVyZWRdQHt0YXNrSWQ9JHRhc2tJZDtzdGF0ZT0nUlVOTklORyc7d3JhcHBlclBpZD0kd3JhcHBlclByb2MuSWQ7c3RhcnRlZEF0PShHZXQtRGF0ZSkuVG9TdHJpbmcoJ28nKTt0aW1lb3V0U2Vjb25kcz0kdGltZW91dDtzY3JpcHQ9JHNhZmVTY3JpcHQ7aG9zdFZlcnNpb249JEhvc3RWZXJzaW9ufTtXcml0ZS1Kc29uQXRvbWljICRzdGF0dXNQYXRoICRzdGF0dXMKICBMb2cgIkFDQ0VQVCB0YXNrPSR0YXNrSWQgd3JhcHBlclBpZD0kKCR3cmFwcGVyUHJvYy5JZCkgdGltZW91dFNlYz0kdGltZW91dCBzY3JpcHQ9JHNhZmVTY3JpcHQiCiAgcmV0dXJuIFtvcmRlcmVkXUB7b2s9JHRydWU7c3RhdGU9J1NUQVJURUQnO3Rhc2tJZD0kdGFza0lkO3dyYXBwZXJQaWQ9JHdyYXBwZXJQcm9jLklkO3RpbWVvdXRTZWNvbmRzPSR0aW1lb3V0O2hvc3RWZXJzaW9uPSRIb3N0VmVyc2lvbjt0cmFuc3BvcnQ9J1RjcExpc3RlbmVyQXN5bmMnfQp9CmZ1bmN0aW9uIEdldC1Bc3luY1Jlc3VsdChbc3RyaW5nXSRUYXNrSWQpewogICR0YXNrSWQ9U2FmZS1UYXNrSWQgJFRhc2tJZDskdGFza0Rpcj1Kb2luLVBhdGggJFJlc3VsdFJvb3QgJHRhc2tJZDskcmVzdWx0UGF0aD1Kb2luLVBhdGggJHRhc2tEaXIgJ3Jlc3VsdC5qc29uJzskc3RhdHVzUGF0aD1Kb2luLVBhdGggJHRhc2tEaXIgJ3N0YXR1cy5qc29uJwogICRyZXN1bHQ9UmVhZC1Kc29uICRyZXN1bHRQYXRoO2lmKCRyZXN1bHQpe3JldHVybiBbb3JkZXJlZF1Ae29rPSR0cnVlO3N0YXRlPSdET05FJzt0YXNrSWQ9JHRhc2tJZDtyZXN1bHQ9JHJlc3VsdDtob3N0VmVyc2lvbj0kSG9zdFZlcnNpb259fQogICRzdGF0dXM9UmVhZC1Kc29uICRzdGF0dXNQYXRoO2lmKC1ub3QgJHN0YXR1cyl7cmV0dXJuIFtvcmRlcmVkXUB7b2s9JHRydWU7c3RhdGU9J05PVF9GT1VORCc7dGFza0lkPSR0YXNrSWQ7aG9zdFZlcnNpb249JEhvc3RWZXJzaW9ufX0KICBpZigkc3RhdHVzLndyYXBwZXJQaWQpeyRwPUdldC1Qcm9jZXNzIC1JZCAoW2ludF0kc3RhdHVzLndyYXBwZXJQaWQpIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlO2lmKCRwKXtyZXR1cm4gW29yZGVyZWRdQHtvaz0kdHJ1ZTtzdGF0ZT0nUlVOTklORyc7dGFza0lkPSR0YXNrSWQ7c3RhcnRlZEF0PSRzdGF0dXMuc3RhcnRlZEF0O3RpbWVvdXRTZWNvbmRzPSRzdGF0dXMudGltZW91dFNlY29uZHM7aG9zdFZlcnNpb249JEhvc3RWZXJzaW9ufX19CiAgcmV0dXJuIFtvcmRlcmVkXUB7b2s9JHRydWU7c3RhdGU9J0VSUk9SJzt0YXNrSWQ9JHRhc2tJZDtlcnJvcj0nQVNZTkNfV1JBUFBFUl9FWElURURfV0lUSE9VVF9SRVNVTFQnO2hvc3RWZXJzaW9uPSRIb3N0VmVyc2lvbn0KfQpmdW5jdGlvbiBDYW5jZWwtQXN5bmNUYXNrKFtzdHJpbmddJFRhc2tJZCl7CiAgJHRhc2tJZD1TYWZlLVRhc2tJZCAkVGFza0lkOyR0YXNrRGlyPUpvaW4tUGF0aCAkUmVzdWx0Um9vdCAkdGFza0lkOyRzdGF0dXM9UmVhZC1Kc29uIChKb2luLVBhdGggJHRhc2tEaXIgJ3N0YXR1cy5qc29uJyk7aWYoJHN0YXR1cyAtYW5kICRzdGF0dXMud3JhcHBlclBpZCl7S2lsbC1UcmVlIC1Qcm9jZXNzSWQgKFtpbnRdJHN0YXR1cy53cmFwcGVyUGlkKX0KICAkcmVzdWx0PVtvcmRlcmVkXUB7b2s9JGZhbHNlO2V4aXRDb2RlPTEyNDt0aW1lZE91dD0kdHJ1ZTtjYW5jZWxlZD0kdHJ1ZTtzdGRlcnI9J0NBTkNFTEVEX0JZX0JSSURHRSc7Y29tcGxldGVkQXQ9KEdldC1EYXRlKS5Ub1N0cmluZygnbycpfTtXcml0ZS1Kc29uQXRvbWljIChKb2luLVBhdGggJHRhc2tEaXIgJ3Jlc3VsdC5qc29uJykgJHJlc3VsdDtyZXR1cm4gW29yZGVyZWRdQHtvaz0kdHJ1ZTtzdGF0ZT0nQ0FOQ0VMRUQnO3Rhc2tJZD0kdGFza0lkO2hvc3RWZXJzaW9uPSRIb3N0VmVyc2lvbn0KfQoKJGxpc3RlbmVyPVtOZXQuU29ja2V0cy5UY3BMaXN0ZW5lcl06Om5ldyhbTmV0LklQQWRkcmVzc106Okxvb3BiYWNrLDg3NjUpOyRsaXN0ZW5lci5TdGFydCgpO0xvZyAiTG9jYWwgY29tbWFuZCBob3N0IFNUQVJUIHRjcDovLzEyNy4wLjAuMTo4NzY1IHYkSG9zdFZlcnNpb24gYXN5bmM9dHJ1ZSIKdHJ5ewogIHdoaWxlKCR0cnVlKXsKICAgICRjbGllbnQ9JGxpc3RlbmVyLkFjY2VwdFRjcENsaWVudCgpOyRzdHJlYW09JG51bGwKICAgIHRyeXsKICAgICAgJHN0cmVhbT0kY2xpZW50LkdldFN0cmVhbSgpOyRzdHJlYW0uUmVhZFRpbWVvdXQ9MTUwMDA7JHN0cmVhbS5Xcml0ZVRpbWVvdXQ9MTUwMDA7JHJlcT1SZWFkLUh0dHBSZXF1ZXN0ICRzdHJlYW0KICAgICAgaWYoJHJlcS5tZXRob2QgLWVxICdPUFRJT05TJyl7U2VuZC1IdHRwSnNvbiAkc3RyZWFtIEB7b2s9JHRydWU7dmVyc2lvbj0kSG9zdFZlcnNpb247YXN5bmNKb2JzPSR0cnVlfTtjb250aW51ZX0KICAgICAgaWYoJHJlcS5tZXRob2QgLWVxICdHRVQnIC1hbmQgJHJlcS5wYXRoIC1lcSAnL2hlYWx0aCcpe1NlbmQtSHR0cEpzb24gJHN0cmVhbSBAe29rPSR0cnVlO3NlcnZpY2U9J0hvbWVEZXNpZ24gTG9jYWwgQ29tbWFuZCBIb3N0Jzt2ZXJzaW9uPSRIb3N0VmVyc2lvbjt0cmFuc3BvcnQ9J1RjcExpc3RlbmVyQXN5bmMnO2FzeW5jSm9icz0kdHJ1ZTt0aW1lPShHZXQtRGF0ZSkuVG9TdHJpbmcoJ28nKX07Y29udGludWV9CiAgICAgICRxdWVyeVRhc2s9UXVlcnktVGFza0lkICRyZXEucGF0aDtpZigkcmVxLm1ldGhvZCAtZXEgJ0dFVCcgLWFuZCAkcXVlcnlUYXNrKXtTZW5kLUh0dHBKc29uICRzdHJlYW0gKEdldC1Bc3luY1Jlc3VsdCAkcXVlcnlUYXNrKTtjb250aW51ZX0KICAgICAgaWYoJHJlcS5tZXRob2QgLWVxICdQT1NUJyAtYW5kICRyZXEucGF0aCAtZXEgJy9ydW4nKXskYm9keT0kcmVxLmJvZHl8Q29udmVydEZyb20tSnNvbjskdGFzaz0kYm9keS50YXNrO2lmKC1ub3QgJHRhc2spe3Rocm93ICd0YXNrIG1pc3NpbmcnfTtTZW5kLUh0dHBKc29uICRzdHJlYW0gKFN0YXJ0LUFzeW5jVGFzayAkdGFzayk7Y29udGludWV9CiAgICAgIGlmKCRyZXEubWV0aG9kIC1lcSAnUE9TVCcgLWFuZCAkcmVxLnBhdGggLWVxICcvY2FuY2VsJyl7JGJvZHk9JHJlcS5ib2R5fENvbnZlcnRGcm9tLUpzb247U2VuZC1IdHRwSnNvbiAkc3RyZWFtIChDYW5jZWwtQXN5bmNUYXNrIChbc3RyaW5nXSRib2R5LnRhc2tJZCkpO2NvbnRpbnVlfQogICAgICBTZW5kLUh0dHBKc29uICRzdHJlYW0gQHtvaz0kZmFsc2U7ZXJyb3I9J05PVF9GT1VORCd9IDQwNAogICAgfWNhdGNoeyRtc2c9JF8uRXhjZXB0aW9uLk1lc3NhZ2U7TG9nICgiRVJST1IgIiskbXNnKTtpZigkc3RyZWFtKXt0cnl7U2VuZC1IdHRwSnNvbiAkc3RyZWFtIEB7b2s9JGZhbHNlO2Vycm9yPSRtc2c7dmVyc2lvbj0kSG9zdFZlcnNpb247YXQ9KEdldC1EYXRlKS5Ub1N0cmluZygnbycpfSA1MDB9Y2F0Y2h7fX19CiAgICBmaW5hbGx5e2lmKCRzdHJlYW0pe3RyeXskc3RyZWFtLkRpc3Bvc2UoKX1jYXRjaHt9fTtpZigkY2xpZW50KXt0cnl7JGNsaWVudC5DbG9zZSgpfWNhdGNoe319fQogIH0KfWZpbmFsbHl7dHJ5eyRsaXN0ZW5lci5TdG9wKCl9Y2F0Y2h7fTtMb2cgJ0xvY2FsIGNvbW1hbmQgaG9zdCBTVE9QJ30K'
    [IO.File]::WriteAllBytes($tmp,[Convert]::FromBase64String($payload))
    $expected='c3f9fca3f5a60d025bd7f0b6c36316969dd055b1'
    $actual=(GitBlobSha1 $tmp).ToLowerInvariant()
    if($actual -ne $expected){Remove-Item $tmp -Force -ErrorAction SilentlyContinue;throw ('EMBEDDED_HOST129_HASH_MISMATCH actual='+$actual+' expected='+$expected)}
    Move-Item -LiteralPath $tmp -Destination $canonical -Force
    $helper=Join-Path $Root 'Apply-EmbeddedHost129.ps1'
    $helperCode=@'
param([string]$HostPath,[string]$ReceiptPath)
$ErrorActionPreference='Continue'
Start-Sleep -Seconds 3
try{
  foreach($p in @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue|Where-Object{$_.CommandLine -and ([string]$_.CommandLine) -match 'HomeDesignLocalCommandHost' -and ([string]$_.CommandLine) -notmatch 'Apply-EmbeddedHost129'})){try{& taskkill.exe /PID ([int]$p.ProcessId) /T /F 2>$null|Out-Null}catch{}}
}catch{}
Start-Sleep -Milliseconds 800
$psi=New-Object Diagnostics.ProcessStartInfo;$psi.FileName='powershell.exe';$psi.UseShellExecute=$true;$psi.WindowStyle=[Diagnostics.ProcessWindowStyle]::Hidden;$psi.Arguments='-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+$HostPath+'"';$proc=[Diagnostics.Process]::Start($psi)
$deadline=(Get-Date).AddSeconds(30);$health=$null
while((Get-Date)-lt $deadline){Start-Sleep -Milliseconds 500;try{$health=Invoke-RestMethod -Uri 'http://127.0.0.1:8765/health' -Method Get -TimeoutSec 2;if($health -and [bool]$health.ok -and [string]$health.version -eq '1.2.9' -and [bool]$health.asyncJobs){break}}catch{}}
$ok=[bool]($health -and [bool]$health.ok -and [string]$health.version -eq '1.2.9' -and [bool]$health.asyncJobs)
$o=[ordered]@{ok=$ok;action='EMBEDDED_HOST129_APPLY_READBACK';hostVersion=$(if($health){[string]$health.version}else{''});hostHealthy=$(if($health){[bool]$health.ok}else{$false});hostAsyncJobs=$(if($health){[bool]$health.asyncJobs}else{$false});pid=$(if($proc){[int]$proc.Id}else{$null});at=(Get-Date).ToString('o')}
if($ReceiptPath){try{$par=Split-Path -Parent $ReceiptPath;if($par){New-Item -ItemType Directory -Force -Path $par|Out-Null};$o|ConvertTo-Json -Depth 20|Set-Content -LiteralPath $ReceiptPath -Encoding UTF8}catch{}}
'@
    Set-Content -LiteralPath $helper -Value $helperCode -Encoding UTF8
    $central=Find-CentralRoot;$receipt=$(if($central){Join-Path $central 'Runtime_Readback\EMBEDDED_HOST129_APPLY_READBACK.json'}else{''})
    $psi=New-Object Diagnostics.ProcessStartInfo;$psi.FileName='powershell.exe';$psi.UseShellExecute=$true;$psi.WindowStyle=[Diagnostics.ProcessWindowStyle]::Hidden;$psi.Arguments='-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+$helper+'" -HostPath "'+$canonical+'" -ReceiptPath "'+$receipt+'"';$proc=[Diagnostics.Process]::Start($psi)
    [ordered]@{ok=$true;action='EMBEDDED_HOST129_RECOVERY_DISPATCHED';taskId=$TaskId;hostBlobSha1=$actual;pid=[int]$proc.Id;expectedHost='1.2.9';sourceFetchMode='INLINE_EMBEDDED_NO_SECONDARY_NETWORK';normalChromeRestarted=$false;generateClicked=$false;creditSpend=$false;oauthChanged=$false;scopeChanged=$false;at=(Get-Date).ToString('o')}|ConvertTo-Json -Depth 10 -Compress
    exit 0
  }catch{
    [ordered]@{ok=$false;action='EMBEDDED_HOST129_RECOVERY_DISPATCHED';taskId=$TaskId;error=$_.Exception.Message;at=(Get-Date).ToString('o')}|ConvertTo-Json -Compress
    exit 2
  }
}

if($KickAgent1141HostRepair){
  try{
    New-Item -ItemType Directory -Force -Path $Root|Out-Null
    $agent=Join-Path $Root 'HomeDesignLocalAgent-1.1.41-direct.ps1'
    $helper=Join-Path $Root 'Kick-Agent1141-AfterHostTask.ps1'
    $url='https://raw.githubusercontent.com/8friend8ship-cloud/notebooklm-webapp-bridge/main/local-agent/releases/1.1.41/HomeDesignLocalAgent.ps1?hdcb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $agent -TimeoutSec 20
    $expected='b24b470dfc439a09446164091d392f886cb8f71e';$actual=(GitBlobSha1 $agent).ToLowerInvariant()
    if($actual -ne $expected){Remove-Item $agent -Force -ErrorAction SilentlyContinue;throw ('AGENT1141_SHA_MISMATCH actual='+$actual+' expected='+$expected)}
    $helperCode=@'
param([string]$AgentPath,[string]$ReceiptPath)
$ErrorActionPreference='Continue'
Start-Sleep -Seconds 4
$started=(Get-Date).ToString('o')
$p=$null;$err=''
try{$psi=New-Object Diagnostics.ProcessStartInfo;$psi.FileName='powershell.exe';$psi.UseShellExecute=$true;$psi.WindowStyle=[Diagnostics.ProcessWindowStyle]::Hidden;$psi.Arguments='-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+$AgentPath+'"';$p=[Diagnostics.Process]::Start($psi)}catch{$err=$_.Exception.Message}
try{if($ReceiptPath){$o=[ordered]@{ok=[bool]$p;action='AGENT1141_DELAYED_HANDOFF';pid=$(if($p){[int]$p.Id}else{$null});agentPath=$AgentPath;startedAt=$started;error=$err;at=(Get-Date).ToString('o')};$o|ConvertTo-Json -Depth 10|Set-Content -LiteralPath $ReceiptPath -Encoding UTF8}}catch{}
'@
    Set-Content -LiteralPath $helper -Value $helperCode -Encoding UTF8
    $central=Find-CentralRoot;$receipt=$(if($central){Join-Path $central 'Runtime_Readback\AGENT_1.1.41_DELAYED_HANDOFF.json'}else{''})
    if($central){New-Item -ItemType Directory -Force -Path (Split-Path -Parent $receipt)|Out-Null}
    $psi=New-Object Diagnostics.ProcessStartInfo;$psi.FileName='powershell.exe';$psi.UseShellExecute=$true;$psi.WindowStyle=[Diagnostics.ProcessWindowStyle]::Hidden;$psi.Arguments='-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+$helper+'" -AgentPath "'+$agent+'" -ReceiptPath "'+$receipt+'"';$p=[Diagnostics.Process]::Start($psi)
    [ordered]@{ok=$true;action='AGENT1141_HOST128_DELAYED_HANDOFF_DISPATCHED';taskId=$TaskId;agentSha=$actual;handoffPid=[int]$p.Id;delaySeconds=4;expectedAgent='1.1.41';expectedHost='1.2.8';normalChromeRestarted=$false;generateClicked=$false;creditSpend=$false;oauthChanged=$false;scopeChanged=$false;at=(Get-Date).ToString('o')}|ConvertTo-Json -Depth 10 -Compress
    exit 0
  }catch{
    [ordered]@{ok=$false;action='AGENT1141_HOST128_DELAYED_HANDOFF_DISPATCHED';taskId=$TaskId;error=$_.Exception.Message;at=(Get-Date).ToString('o')}|ConvertTo-Json -Compress
    exit 2
  }
}

if($SetupCaptureBridgeAutoSync){
  try{
    $setupDir=Join-Path $Root 'capture'
    New-Item -ItemType Directory -Force -Path $setupDir|Out-Null
    $setup=Join-Path $setupDir 'Setup-NotebookLMCaptureBridgeAutoSync.ps1'
    $url='https://raw.githubusercontent.com/8friend8ship-cloud/notebooklm-webapp-bridge/main/local-agent/capture/Setup-NotebookLMCaptureBridgeAutoSync.ps1?hdcb='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $setup -TimeoutSec 20
    $output=& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $setup 2>&1
    $rc=$LASTEXITCODE
    $text=($output|Out-String).Trim()
    if($rc -ne 0){throw ('CAPTUREBRIDGE_SETUP_FAILED rc='+$rc+' output='+$text)}
    [ordered]@{ok=$true;action='NOTEBOOKLM_CAPTUREBRIDGE_AUTOSYNC_SETUP';taskId=$TaskId;output=$text;at=(Get-Date).ToString('o')}|ConvertTo-Json -Depth 10 -Compress
    exit 0
  }catch{
    [ordered]@{ok=$false;action='NOTEBOOKLM_CAPTUREBRIDGE_AUTOSYNC_SETUP';taskId=$TaskId;error=$_.Exception.Message;at=(Get-Date).ToString('o')}|ConvertTo-Json -Compress
    exit 2
  }
}

if($CreateLocalSaveSmoke){
  try{
    $dir='C:\HomeDesignAutomationV7\CaptureBridge\INBOX\NotebookLM'
    New-Item -ItemType Directory -Force -Path $dir|Out-Null
    $file=Join-Path $dir '_TEST_NOTEBOOKLM_LOCAL_SAVE.txt'
    Set-Content -LiteralPath $file -Value ('NOTEBOOKLM_LOCAL_SAVE_TEST '+(Get-Date).ToString('o')) -Encoding UTF8
    $item=Get-Item -LiteralPath $file -ErrorAction Stop
    [ordered]@{ok=$true;action='NOTEBOOKLM_LOCAL_SAVE_SMOKE';folder=$dir;file=$file;size=[int64]$item.Length;exists=$true;at=(Get-Date).ToString('o')}|ConvertTo-Json -Compress
    exit 0
  }catch{
    [ordered]@{ok=$false;action='NOTEBOOKLM_LOCAL_SAVE_SMOKE';error=$_.Exception.Message;at=(Get-Date).ToString('o')}|ConvertTo-Json -Compress
    exit 2
  }
}

function Read-Json([string]$Path){
  if(-not(Test-Path -LiteralPath $Path)){return $null}
  try{return Get-Content -LiteralPath $Path -Raw -Encoding UTF8|ConvertFrom-Json}catch{return $null}
}
function Get-WorkBudgetSeconds([string]$Kind,[int]$MediaSeconds){
  $m=[Math]::Max(0,$MediaSeconds)
  switch($Kind){
    'AUDIO' { return [Math]::Max(120,[int]([Math]::Ceiling($m*1.5)+60)) }
    'VIDEO' { return [Math]::Max(300,[int]([Math]::Ceiling($m*3.0)+180)) }
    'IMAGE' { return 180 }
    'TEXT'  { return 120 }
    default { return $(if($m -gt 0){[Math]::Max(180,[int]([Math]::Ceiling($m*2.0)+120))}else{180}) }
  }
}
function Read-OutputProgress([string]$Path){
  $o=[ordered]@{configured=$false;exists=$false;kind='';sizeBytes=0;lastWrite='';ageSeconds=$null;progressing=$false}
  if([string]::IsNullOrWhiteSpace($Path)){return $o}
  $o.configured=$true
  try{
    if(Test-Path -LiteralPath $Path){
      $o.exists=$true;$item=Get-Item -LiteralPath $Path -ErrorAction Stop
      if($item.PSIsContainer){$o.kind='DIRECTORY'}else{$o.kind='FILE';$o.sizeBytes=[int64]$item.Length;$o.lastWrite=$item.LastWriteTime.ToString('o');$o.ageSeconds=[int][Math]::Floor(((Get-Date)-$item.LastWriteTime).TotalSeconds)}
      if($null -ne $o.ageSeconds -and $o.ageSeconds -le 90){$o.progressing=$true}
    }
  }catch{}
  return $o
}
$health=$null;$healthError='';try{$health=Invoke-RestMethod -Uri ("http://127.0.0.1:$HostPort/health") -Method Get -TimeoutSec 3}catch{$healthError=$_.Exception.Message}
$hostResult=$null;$hostResultError='';try{$hostResult=Invoke-RestMethod -Uri ("http://127.0.0.1:$HostPort/result?taskId="+[Uri]::EscapeDataString($TaskId)) -Method Get -TimeoutSec 3}catch{$hostResultError=$_.Exception.Message}
$status=Read-Json $StatusPath;$result=Read-Json $ResultPath;$wrapperPid=$null;$wrapperAlive=$false
if($status -and $status.wrapperPid){try{$wrapperPid=[int]$status.wrapperPid;$wrapperAlive=[bool](Get-Process -Id $wrapperPid -ErrorAction SilentlyContinue)}catch{}}
$resolvedKind=$TaskKind;if($resolvedKind -eq 'AUTO'){if($ExpectedMediaSeconds -gt 0){$resolvedKind='VIDEO'}else{$resolvedKind='TEXT'}}
$workBudget=Get-WorkBudgetSeconds $resolvedKind $ExpectedMediaSeconds;$startedAt=$null;$runAgeSeconds=$null
if($status -and $status.startedAt){try{$startedAt=[datetime]$status.startedAt;$runAgeSeconds=[int][Math]::Floor(((Get-Date)-$startedAt).TotalSeconds)}catch{}}
$outputProgress=Read-OutputProgress $ExpectedOutputPath
$state='UNKNOWN';$ok=$false;$problem=''
if(-not $health -or -not [bool]$health.ok){$state='HOST_DOWN';$problem='Local Command Host health check failed.'}
elseif($result -or ($hostResult -and [string]$hostResult.state -eq 'DONE')){$state='DONE';$ok=$true}
elseif(($hostResult -and [string]$hostResult.state -eq 'RUNNING') -or ($status -and $wrapperAlive)){if($outputProgress.progressing){$state='PROGRESSING';$ok=$true}elseif($null -ne $runAgeSeconds -and $runAgeSeconds -gt $workBudget){$state='RUNNING_OVER_BUDGET';$problem='Work started but exceeded media-aware budget without recent output progress.'}else{$state='START_CONFIRMED';$ok=$true}}
elseif($status -and -not $wrapperAlive){$state='START_LOST';$problem='status.json exists but wrapper process is not alive and no result.json exists.'}
elseif($hostResult -and [string]$hostResult.state -eq 'ERROR'){$state='HOST_TASK_ERROR';$problem=[string]$hostResult.error}
else{if($ClaimedAgeSeconds -ge $StartGraceSeconds){$state='CLAIMED_START_DELAY';$problem='Claimed but no Host RUNNING/DONE evidence within start grace window.'}else{$state='CLAIMED_PENDING_START';$problem='Claimed and still inside the short start grace window.'}}
$out=[ordered]@{ok=$ok;action='NOTEBOOKLM_CLAIM_START_BRIDGE_TEST_V2';taskId=$TaskId;state=$state;checkedAt=(Get-Date).ToString('o');hostHealthy=$(if($health){[bool]$health.ok}else{$false});hostVersion=$(if($health){[string]$health.version}else{''});hostAsyncJobs=$(if($health){[bool]$health.asyncJobs}else{$false});problem=$problem}
$out|ConvertTo-Json -Depth 30 -Compress
if($state -in @('DONE','PROGRESSING','START_CONFIRMED','CLAIMED_PENDING_START')){exit 0}else{exit 2}
