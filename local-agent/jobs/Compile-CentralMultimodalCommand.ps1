param(
  [Parameter(Mandatory=$true)][string]$CommandJson,
  [string]$TemplatePath = '',
  [string]$OutputPath = ''
)
$ErrorActionPreference='Stop'
function Get-Prop($o,$n,$d=$null){ if($null -ne $o.PSObject.Properties[$n]){return $o.$n}; return $d }
function Safe-Arr($v){ if($null -eq $v){return @()}; if($v -is [System.Array]){return @($v)}; return @($v) }
function Slug($s){ if([string]::IsNullOrWhiteSpace($s)){return 'default'}; return (($s -replace '[^A-Za-z0-9가-힣_-]','-').Trim('-')).ToLowerInvariant() }
$cmd=$CommandJson|ConvertFrom-Json
$projectKey=[string](Get-Prop $cmd 'projectKey' '')
$goal=[string](Get-Prop $cmd 'goal' '')
$sourceRefs=Safe-Arr (Get-Prop $cmd 'sourceRefs' @())
if([string]::IsNullOrWhiteSpace($projectKey)){throw 'PROJECT_KEY_REQUIRED'}
if([string]::IsNullOrWhiteSpace($goal)){throw 'GOAL_REQUIRED'}
if($sourceRefs.Count -eq 0){throw 'SOURCE_REFS_REQUIRED'}
$language=[string](Get-Prop $cmd 'language' 'ko-KR')
$audience=[string](Get-Prop $cmd 'audience' 'general')
$tone=[string](Get-Prop $cmd 'tone' 'clear')
$outputs=Safe-Arr (Get-Prop $cmd 'outputChecklist' @('NOTEBOOKLM_REPORT_PDF'))
$variants=Safe-Arr (Get-Prop $cmd 'variants' @())
if($variants.Count -eq 0){$variants=@([pscustomobject]@{variantKey='default';settings=[pscustomobject]@{}})}
$parentId=('CMD_{0}_{1}' -f (Slug $projectKey),(Get-Date -Format 'yyyyMMdd_HHmmss'))
$children=@()
foreach($otype in $outputs){
  foreach($v in $variants){
    $variantKey=[string](Get-Prop $v 'variantKey' 'default')
    $settings=Get-Prop $v 'settings' ([pscustomobject]@{})
    if($null -eq $settings.PSObject.Properties['language']){$settings|Add-Member NoteProperty language $language}
    if($null -eq $settings.PSObject.Properties['audience']){$settings|Add-Member NoteProperty audience $audience}
    if($null -eq $settings.PSObject.Properties['tone']){$settings|Add-Member NoteProperty tone $tone}
    $taskId=('{0}_{1}_{2}_{3}' -f (Slug $projectKey),(Slug ([string]$otype)),(Slug $variantKey),(Get-Date -Format 'yyyyMMdd_HHmmssfff'))
    $source=[ordered]@{parentCommandId=$parentId;projectKey=$projectKey;outputType=[string]$otype;variantKey=$variantKey;settings=$settings;sourceRefs=$sourceRefs}
    $success=[ordered]@{purposeFitRequired=$true;minimumQualityScore=80;minimumUsabilityScore=80;minimumGoalAlignmentScore=85;readbackRequired=$true;promotionRequiresAuditPass=$true}
    $instruction=[ordered]@{goal=$goal;successCriteria=$success;savePolicy='SAVE_TO_PROJECT_DRIVE_AND_RETURN_ID_URL';readbackPolicy='VERIFY_SAVED_FILE_AND_CONTENT';auditPolicy='CENTRAL_RESULT_AUDIT_V1'}
    $children += [pscustomobject]@{
      TASK_ID=$taskId; CONTENT_ID=$projectKey; TASK_TYPE='LOCAL_POWERSHELL_ASYNC'; TITLE=('{0} {1}' -f $otype,$variantKey);
      SOURCE_TEXT=($source|ConvertTo-Json -Depth 20 -Compress); INSTRUCTION=($instruction|ConvertTo-Json -Depth 20 -Compress);
      LANGUAGE=$language; TIMEOUT_SECONDS=45; STATUS='READY'; PARENT_COMMAND_ID=$parentId; OUTPUT_TYPE=[string]$otype; VARIANT_KEY=$variantKey;
      AUDIT=[ordered]@{goal=$goal;projectKey=$projectKey;outputType=[string]$otype;variantKey=$variantKey;checks=@('SOURCE_TRACEABLE','OUTPUT_READABLE','GOAL_ALIGNMENT','PRACTICAL_USABILITY','QUALITY_LEVEL','NO_CRITICAL_ERROR','RESULT_READBACK');thresholds=$success}
    }
  }
}
$result=[ordered]@{ok=$true;action='CENTRAL_MULTIMODAL_COMMAND_COMPILE';parentCommandId=$parentId;projectKey=$projectKey;goal=$goal;childCount=$children.Count;children=$children;postResultPipeline=@('RESULT_READBACK','CENTRAL_OPENAI_AUDIT','PURPOSE_FIT_GATE','AUDIT_SHEET_WRITE','QUEENS_OR_SEED_CLASSIFY','TEMPLATE_PROMOTION_IF_PASS','FAILURE_LESSON_WRITEBACK');at=(Get-Date).ToString('o')}
$json=$result|ConvertTo-Json -Depth 30
if(-not [string]::IsNullOrWhiteSpace($OutputPath)){ $dir=Split-Path -Parent $OutputPath;if($dir){New-Item -ItemType Directory -Force -Path $dir|Out-Null};Set-Content -LiteralPath $OutputPath -Value $json -Encoding UTF8 }
$json
