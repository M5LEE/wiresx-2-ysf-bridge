param([string]$Bin)
$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
. (Join-Path $Bin 'PublicRuntime.ps1')
. (Join-Path $Bin 'FirstRun.ps1')
$module=Join-Path $Bin 'ExistingStation.ps1';if(!(Test-Path $module)){throw 'Existing working station import is not implemented'};. $module
$base=Join-Path (Split-Path $Bin) ('tests\migration-'+[Guid]::NewGuid().ToString('N'));$source=Join-Path $base 'source';$script:Root=Join-Path $base 'new-station';$checks=0
function Check($ok,$name){if(!$ok){throw ('FAIL: '+$name)};$script:checks++}
function Refuses($action,$name){$bad=$false;try{& $action|Out-Null}catch{$bad=$true};Check $bad $name}
try{
 $null=New-Item -ItemType Directory -Force (Join-Path $source 'private-baseline')
 @'
$fixture=Join-Path $private 'startup-example.json'
$real=New-Object IO.Ports.SerialPort 'COM101',38400
$virt=New-Object IO.Ports.SerialPort 'COM103',38400
'@|Set-Content (Join-Path $source 'voice-adapter.ps1')
 @(@{Path='HKLM:\SYSTEM\CurrentControlSet\Enum\USB\Fixture\A';FriendlyName='HRI-200 Communication device A (COM101)'},@{Path='HKLM:\SYSTEM\CurrentControlSet\Enum\COM0COM\PORT\CNCA0';FriendlyName='com0com - serial port emulator (COM102)'})|ConvertTo-Json|Set-Content (Join-Path $source 'discovery-name-backup.json')
 @{Gateway='TEST1/WX';Tag='bridgeExample'}|ConvertTo-Json|Set-Content (Join-Path $source 'progress-bridgeExample.json')
 $query='D1M0045'+'7000'+(('433.00000+000.00000'+('0'*13))*2)+'F';$reply=$query.Substring(0,7)+'5000'+$query.Substring(11,64)+'0'
 $capture=@{VoiceStored=$false;HriIdentityStored=$false;Records=@(@{Direction='ClientToHri';Body='P010000'},@{Direction='ClientToHri';Body=$query},@{Direction='HriToClient';Body=$reply},@{Direction='HriToClient';Body='D1V0001X'},@{Direction='HriToClient';Body='D1C000B00005TEST10'},@{Direction='HriToClient';Body='D1P000B00005TEST10'},@{Direction='HriToClient';Body='D1B00010'},@{Direction='HriToClient';Body='B0 0    0000000'})}
 $input=Join-Path $source 'private-baseline\startup-example.json';$capture|ConvertTo-Json -Depth 6|Set-Content $input
 $before=@{};foreach($f in Get-ChildItem $source -File -Recurse){$before[$f.FullName]=(Get-FileHash $f.FullName).Hash}
 $ops=@{Native={return 'C:\Program Files (x86)\YAESUMUSEN\WIRES-X\Wires-X.exe'};Pair={param($a,$b)return ($a -ceq 'COM102' -and $b -ceq 'COM103')}}
 $s=Import-ExistingStation $source $ops
 Check ($s.Gateway -ceq 'TEST1/WX' -and !$s.OwnRoomId) 'identity inherited without entered callsign or fixed room'
 Check ($s.PhysicalPort -ceq 'COM101' -and $s.NativePort -ceq 'COM102' -and $s.AdapterPort -ceq 'COM103') 'existing port roles preserved'
 Check ((Get-Station -RequireProfile).RadioProfileSha256 -cmatch '^[A-F0-9]{64}$') 'existing metadata revalidated and pinned'
 $own=Get-Content (Join-Path $script:Root 'private-baseline\radio-profile.json') -Raw|ConvertFrom-Json
 Check (@($own.Records|Where-Object {$_.Body -eq 'P010000'}).Count -eq 0) 'startup polling excluded from metadata profile'
 foreach($f in Get-ChildItem $source -File -Recurse){Check ((Get-FileHash $f.FullName).Hash -ceq $before[$f.FullName]) 'source remains byte identical'}
 Refuses {Import-ExistingStation $source $ops} 'existing destination station never overwritten'
 $script:Root=Join-Path $base 'custom-ysf';$custom=Import-ExistingStation $source $ops -YsfCallsign 'TEST9/YSF'
 Check ($custom.Gateway -ceq 'TEST9/YSF' -and (Get-Station -RequireProfile).RadioProfileSha256) 'chosen YSF bridge callsign overrides inherited network identifier without changing native profile'
 $script:Root=Join-Path $base 'refused';$ops.Pair={return $false};Refuses {Import-ExistingStation $source $ops} 'unverified port pair refused';Check (!(Test-Path (Join-Path $script:Root 'station.json'))) 'pair refusal publishes no station'
 $ops.Pair={return $true};$capture.Records+=@{Direction='ClientToHri';Body='D1E008900BAD'};$capture|ConvertTo-Json -Depth 6|Set-Content $input
 Refuses {Import-ExistingStation $source $ops} 'voice frames refused';Check (!(Test-Path (Join-Path $script:Root 'station.json'))) 'voice refusal publishes no station'
 'RESULT: '+$checks+' existing-station migration checks passed; synthetic files/injected discovery only; no serial, driver or native actions'
}finally{if(Test-Path $base){Remove-Item $base -Recurse -Force}}
