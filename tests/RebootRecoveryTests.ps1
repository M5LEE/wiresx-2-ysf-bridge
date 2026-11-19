param([Parameter(Mandatory=$true)][string]$Bin)
$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
. (Join-Path $Bin 'PublicRuntime.ps1')
if(!(Get-Command Invoke-InterruptedBridgeRecovery -ErrorAction SilentlyContinue)){throw 'Missing safe interrupted-session recovery'}
$script:Root=Join-Path $env:USERPROFILE ('WX-recovery-test-'+[Guid]::NewGuid().ToString('N').Substring(0,10))
New-Item -ItemType Directory (Join-Path $script:Root 'launcher-state') -Force|Out-Null
$tag='bridge'+'a'*32;$manifest=Join-Path $script:Root 'launcher-state\owner.json'
$station=@{PhysicalPort='COM3';NativePort='COM4';AdapterPort='COM5'}
$entries=@(@{Path='HKLM:\SYSTEM\CurrentControlSet\Enum\USB\VID_26AA&PID_0002\TEST';FriendlyName='HRI-200 Communication device A (COM3)'},@{Path='HKLM:\SYSTEM\CurrentControlSet\Enum\COM0COM\TEST';FriendlyName='com0com - serial port emulator (COM4)'})
$entries|ConvertTo-Json|Set-Content (Join-Path $script:Root 'discovery-name-backup.json')
$owner=@{Version=1;Root=$script:Root;Tag=$tag;State='Running';Supervisor=@{Pid=123;Created='2026-01-01T00:00:00Z';Root=$script:Root;Tag=$tag};Aliases=@(@{Path=$entries[0].Path;Original=$entries[0].FriendlyName;Alias='WIRESX to YSF physical HRI (COM3)';Pending=$true},@{Path=$entries[1].Path;Original=$entries[1].FriendlyName;Alias='HRI-200 Communication device A (COM4)';Pending=$true})}
$script:values=@{};foreach($a in $owner.Aliases){$script:values[$a.Path]=$a.Alias};$script:writes=0;$script:blocked=$true
$ops=@{AssertIdle={param($o)if($script:blocked){throw 'CloseWiresXBeforeRecovery'}};ReadAlias={param($path)return $script:values[$path]};WriteAlias={param($path,$value)$script:writes++;$script:values[$path]=$value}}
function SaveFixture{$owner|ConvertTo-Json -Depth 8|Set-Content $manifest}
function Check($ok,$message){if(!$ok){throw $message};$script:passed++}
$script:passed=0;SaveFixture
$refused=$false;try{Invoke-InterruptedBridgeRecovery -Station $station -Ops $ops}catch{$refused=$_.Exception.Message -ceq 'CloseWiresXBeforeRecovery'}
Check ($refused -and $script:writes -eq 0 -and (Test-Path $manifest)) 'Live native session must block recovery without any alias writes'
$script:blocked=$false;$script:values[$entries[1].Path]='Foreign name';$refused=$false
try{Invoke-InterruptedBridgeRecovery -Station $station -Ops $ops}catch{$refused=$_.Exception.Message -ceq 'RecoveryAliasChanged'}
Check ($refused -and $script:writes -eq 0) 'Validate every alias before the first write'
$script:values[$entries[1].Path]=$owner.Aliases[1].Alias
$result=Invoke-InterruptedBridgeRecovery -Station $station -Ops $ops
Check ($result.Recovered -and !(Test-Path $manifest)) 'Successful recovery must release only the stale owner'
Check ($script:values[$entries[0].Path] -ceq $entries[0].FriendlyName -and $script:values[$entries[1].Path] -ceq $entries[1].FriendlyName) 'Both exact original names must be restored'
Check ((Test-Path $result.Backup) -and (Test-Path $result.ArchivedOwner)) 'Preserve original and completed ownership evidence'
SaveFixture;$owner.Root='C:\other-station';SaveFixture;$oldWrites=$script:writes;$refused=$false
try{Invoke-InterruptedBridgeRecovery -Station $station -Ops $ops}catch{$refused=$_.Exception.Message -ceq 'InvalidRecoveryOwner'}
Check ($refused -and $script:writes -eq $oldWrites) 'Foreign owner must not be recovered'
$owner.Root=$script:Root;SaveFixture;foreach($a in $owner.Aliases){$script:values[$a.Path]=$a.Alias}
$script:failSecond=$true
$ops.WriteAlias={param($path,$value)if($script:failSecond -and $path -ceq $entries[1].Path){$script:failSecond=$false;throw 'SyntheticRestoreFailure'};$script:writes++;$script:values[$path]=$value}
$refused=$false;try{Invoke-InterruptedBridgeRecovery -Station $station -Ops $ops}catch{$refused=$_.Exception.Message -ceq 'SyntheticRestoreFailure'}
Check ($refused -and (Test-Path $manifest) -and $script:values[$entries[0].Path] -ceq $entries[0].FriendlyName) 'Partial restore retains the owner and its recovery evidence'
$result=Invoke-InterruptedBridgeRecovery -Station $station -Ops $ops
Check ($result.Recovered -and !(Test-Path $manifest) -and $script:values[$entries[1].Path] -ceq $entries[1].FriendlyName) 'Retry accepts an already-restored alias and finishes the remaining owned alias'
SaveFixture;$held=[IO.File]::Open((Join-Path (Split-Path $manifest) 'owner.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None);$refused=$false;$oldWrites=$script:writes
try{try{Invoke-InterruptedBridgeRecovery -Station $station -Ops $ops}catch{$refused=$true}}finally{$held.Dispose()}
Check ($refused -and $script:writes -eq $oldWrites -and (Test-Path $manifest)) 'Concurrent owner lock blocks recovery before any mutation'
@{Pass=$true;Assertions=$script:passed;HardwareTouched=$false;Fixture=$script:Root}|ConvertTo-Json -Compress
