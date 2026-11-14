param([Parameter(Mandatory=$true)][string]$AdapterPath,[Parameter(Mandatory=$true)][string]$AssemblyPath)
$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
[Reflection.Assembly]::LoadFrom($AssemblyPath)|Out-Null
$tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseFile($AdapterPath,[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'AdapterParse'}
$proofNodes=@($ast.FindAll({param($n)$n -is [Management.Automation.Language.IfStatementAst] -and $n.Extent.Text.StartsWith('if($now-$lastProofCheck -ge 1000)')},$true))
$gateNodes=@($ast.FindAll({param($n)$n -is [Management.Automation.Language.IfStatementAst] -and $n.Extent.Text.StartsWith('if($wasActive -and !$active')},$true))
if($proofNodes.Count -ne 1 -or $gateNodes.Count -ne 1){throw 'ProductionProofGateNotFound'}
$proofBlock=[ScriptBlock]::Create($proofNodes[0].Extent.Text);$gateBlock=[ScriptBlock]::Create($gateNodes[0].Extent.Text)
$networkNodes=@($ast.FindAll({param($n)$n -is [Management.Automation.Language.IfStatementAst] -and $n.Extent.Text.StartsWith('if($configured -and $roomVerified -and $linkHealthy -and $ForwardVoice){Send-Batch ($engine.OnReflector(')},$true))
if($networkNodes.Count -ne 1){throw 'ActualNetworkGateNotFound'};$networkBlock=[ScriptBlock]::Create($networkNodes[0].Extent.Text)
foreach($name in @('Read-RoomProof')){foreach($f in @($ast.FindAll({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -ceq $name},$true))){Invoke-Expression $f.Extent.Text}}
$root=Join-Path (Split-Path $AssemblyPath) ('proof-test-'+[Guid]::NewGuid().ToString('N'));[IO.Directory]::CreateDirectory($root)|Out-Null
$Tag='testproof';$start=[DateTime]::UtcNow.AddHours(-1);$app=[pscustomobject]@{Id=123;StartTime=$start}
function Get-Process {param($Name)return $app}
function Send-Batch($b,[bool]$endingOnly=$false){foreach($s in $b.Serial){if($s.StartsWith('P')){throw 'PhysicalControl'};if($s.StartsWith('D1R')){$script:voiceOut++}};if($b.Network.Count){throw 'UnexpectedNetworkOutput'}}
function Check($ok,$why){$script:checks++;if(!$ok){throw $why}}
function Proof([bool]$connected,[string]$key,[string]$error='',[string]$recover=''){
 return [pscustomobject]@{Tag=$Tag;Method='NativeMainLog';ControlId=1014;AppPid=123;AppStartUtc=$start.ToUniversalTime().ToString('o');Connected=$connected;RoomId=$(if($connected){'12345'}else{$null});ConnectionKey=$key;RecoveryKey=$recover;Error=$error;Utc=[DateTime]::UtcNow.ToString('o')}
}
function Save-Proof($proof){[IO.File]::WriteAllText((Join-Path $root ('room-proof-'+$Tag+'.json')),($proof|ConvertTo-Json -Compress))}
function New-Voice([int]$seq){return ,[CumbriaCQ.Offline.YsfWire]::Packet('TESTVIA','TESTCALL',[CumbriaCQ.Offline.YsfWire]::VoiceFrame((New-Object byte[] 65),($seq%8),7,50,'TESTCALL'),$seq,$false)}
$script:checks=0;$script:voiceOut=0
try{
 foreach($mode in @('same','new-epoch','disconnect','stale','wrong-pid','wrong-start','wrong-tag','barrier','link-down','forward-off','not-configured','blocked-end','blocked-header')){
  $engine=[CumbriaCQ.Offline.VoiceEngine]::new('TESTGW/WX',50,'D1C000B00005TEST10','B0 0    0000000',$false,$true)
  $configured=$true;$ForwardVoice=$true;$linkHealthy=$true;$roomVerified=$false;$wasActive=$false;$proofPaused=$false;$currentRoom=$null;$connectionKey=$null;$roomBarrier=$null;$lastProofCheck=-1000;$now=0L
  $ysfReload=New-Object PSObject;$ysfReload|Add-Member ScriptMethod IsHealthy {param($time)return $linkHealthy}
  Save-Proof (Proof $true 'epoch|owner|1');. $proofBlock;$active=$configured -and $roomVerified -and $linkHealthy -and $ForwardVoice;. $gateBlock;$wasActive=$active
  Check $roomVerified 'Initial exact-bound fresh proof must be accepted'
  $null=$engine.OnReflector([CumbriaCQ.Offline.YsfWire]::Packet('TESTVIA','TESTCALL',[CumbriaCQ.Offline.YsfWire]::HeaderFrame('TESTCALL',50,$false),0,$false),0)
  for($n=1;$n -le 9;$n++){$null=$engine.OnReflector((New-Voice $n),($n*100));$null=$engine.Tick($n*100)}
  $now=1000L;$p=Proof $false '' 'NativeLogRead' 'epoch|owner|1'
  switch($mode){'disconnect'{$p.Error='';$p.RecoveryKey=''} 'stale'{$p.Utc=[DateTime]::UtcNow.AddSeconds(-20).ToString('o')} 'wrong-pid'{$p.AppPid=999} 'wrong-start'{$p.AppStartUtc='2000-01-01T00:00:00Z'} 'wrong-tag'{$p.Tag='foreign'} 'barrier'{$roomBarrier='epoch|owner|1'}}
  Save-Proof $p;. $proofBlock;$active=$configured -and $roomVerified -and $linkHealthy -and $ForwardVoice;. $gateBlock;$wasActive=$active
  Check (!$roomVerified -and !$active) 'Unavailable or invalid proof must close forwarding immediately'
  Check ($engine.Tick(1100).Serial.Count -eq 0) 'Old queued speech must not drain while proof is unavailable'
  if($mode -in @('blocked-end','blocked-header')){
   $counts=@{GateDrops=0};$end=$mode -eq 'blocked-end';$packet=[CumbriaCQ.Offline.YsfWire]::Packet('TESTVIA','TESTCALL',[CumbriaCQ.Offline.YsfWire]::HeaderFrame('TESTCALL',50,$end),10,$end);. $networkBlock
   Check ($counts.GateDrops -eq 1) 'A blocked over boundary must not be forwarded'
  }
  $now=2500L;$p=Proof $true $(if($mode -eq 'new-epoch'){'epoch|owner|2'}else{'epoch|owner|1'})
  if($mode -eq 'link-down'){$linkHealthy=$false};if($mode -eq 'forward-off'){$ForwardVoice=$false};if($mode -eq 'not-configured'){$configured=$false}
  Save-Proof $p;. $proofBlock;$active=$configured -and $roomVerified -and $linkHealthy -and $ForwardVoice;. $gateBlock;$wasActive=$active
  # Even after other gates recover, a hard fault must have erased the old context.
  $linkHealthy=$true;$ForwardVoice=$true;$configured=$true
  $null=$engine.OnReflector((New-Voice 26),2600);$b=$engine.Tick(2700)
  $wanted=if($mode -eq 'same'){10}else{9}
  Check ($engine.DiagnosticCounts['receive-voice-admitted'] -eq $wanted) ('Actual proof-dispatch recovery policy: '+$mode)
  Check (@($b.Serial|Where-Object {$_.StartsWith('D1R')}).Count -eq $(if($mode -eq 'same'){1}else{0})) ('No stale speech after '+$mode)
 }
 Write-Output ('ROOM_PROOF_ADAPTER_PASS checks='+$script:checks+' actual_dispatch=true hardware_touched=false')
}finally{Remove-Item $root -Recurse -Force}
