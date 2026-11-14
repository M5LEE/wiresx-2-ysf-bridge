# Copyright (c) 2026 M5LEE.
# SPDX-License-Identifier: GPL-3.0-or-later
param([string]$Bin)
$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
. (Join-Path $Bin 'PublicRuntime.ps1')
. (Join-Path $Bin 'FirstRun.ps1')
$script:Root=Join-Path (Split-Path $Bin) ('tests\first-run-'+[Guid]::NewGuid().ToString('N'))
$fixtureRoot=$script:Root
$checks=0
function Check($v,$n){if(!$v){throw ('FAIL: '+$n)};$script:checks++;Write-Output ('PASS: '+$n)}
try{
 New-Item -ItemType Directory -Force $script:Root|Out-Null
 $child=Invoke-BoundedSetupProcess $env:ComSpec '/d /c echo READY' $script:Root @{}
 Check ($child.ExitCode -eq 0 -and $child.Output.Trim() -ceq 'READY') 'bounded child captures real successful exit code and output'
 $child=Invoke-BoundedSetupProcess $env:ComSpec '/d /c exit 7' $script:Root @{}
 Check ($child.ExitCode -eq 7) 'bounded child preserves failed exit codes'
 function Get-CimInstance {param($ClassName,$Filter);return $script:TestDevices}
 $script:TestDevices=@([pscustomobject]@{Name='Renamed physical port (COM8)';DeviceID='USB\FIXTURE';HardwareID=@('USB\VID_26AA&PID_0002');ConfigManagerErrorCode=0},[pscustomobject]@{Name='HRI-200 Communication device A (COM9)';DeviceID='COM0COM\FIXTURE';HardwareID=@('com0com\port');ConfigManagerErrorCode=0})
 Check ((Find-HriPort '') -ceq 'COM8') 'HRI discovery uses genuine USB hardware ID, not a renamed or virtual friendly name'
 $bad=$false;try{Find-HriPort 'COM9'}catch{$bad=$true};Check $bad 'explicit non-HRI selection is not silently replaced'
 Remove-Item Function:\Get-CimInstance
 $pairs=@(ConvertFrom-PairList "CNCA0 PortName=COM#,RealPortName=COM4`r`nCNCB0 PortName=COM#,RealPortName=COM5`r`nCNCA1 PortName=COM20`r`nCNCB1 PortName=COM21")
 Check ($pairs.Count -eq 2 -and $pairs[0].NativePort -ceq 'COM4' -and $pairs[1].AdapterPort -ceq 'COM21') 'actual setupc list syntax maps complete pairs'
 Check (@(ConvertFrom-PairList 'CNCA2 PortName=COM22').Count -eq 0) 'half-pair never adopted'
 $bad=$false;try{ConvertFrom-PairList "CNCA0 PortName=COM4`nCNCB0 PortName=COM4"}catch{$bad=$true};Check $bad 'same endpoint pair refused'
 $script:events=New-Object 'System.Collections.Generic.List[string]';$script:inventory=@()
 $ops=@{Guard={};Native={'C:\Program Files (x86)\YAESUMUSEN\WIRES-X\Wires-X.exe'};Physical={'COM3'};Installed={$false};Install={$script:events.Add('Install')};Pairs={return $script:inventory};Create={$script:events.Add('Create');$script:inventory=@([pscustomobject]@{Id=2;NativePort='COM12';AdapterPort='COM13'})};Healthy={param($pair)$true}}
 $station=Initialize-StationConnections -Gateway 'TEST1/WX' -OwnRoomId '12345' -Ops $ops
 Check (($script:events -join ',') -ceq 'Install,Create') 'fresh setup installs dependency then creates pair'
 Check ($station.PhysicalPort -ceq 'COM3' -and $station.NativePort -ceq 'COM12' -and $station.AdapterPort -ceq 'COM13') 'ports assigned without asking user for virtual COM numbers'
 Check ((Get-Station).NativePort -ceq 'COM12') 'automatic result reaches real station store'
 $script:events.Clear();$ops.Installed={$true};$again=Initialize-StationConnections -Gateway 'TEST1/WX' -OwnRoomId '12345' -Ops $ops
 Check ($script:events.Count -eq 0) 'repeat setup reuses verified saved pair without duplicate installation'
 $hash=(Get-FileHash (Join-Path $script:Root 'station.json')).Hash
 $ops.Guard={throw 'ExistingAdapter'};$bad=$false;try{Initialize-StationConnections -Gateway 'TEST1/WX' -OwnRoomId '12345' -Ops $ops}catch{$bad=$true}
 Check ($bad -and $script:events.Count -eq 0) 'active bridge blocks all provisioning writes'
 $ops.Guard={};$ops.Healthy={param($pair)$false};$bad=$false;try{Initialize-StationConnections -Gateway 'TEST1/WX' -OwnRoomId '12345' -Ops $ops}catch{$bad=$true}
 Check $bad 'blocked or unhealthy driver is never reported ready'
 Check ((Get-FileHash (Join-Path $script:Root 'station.json')).Hash -ceq $hash) 'failed setup preserves station'
 $ops.Healthy={param($pair)$true};$ops.Physical={throw 'More than one HRI-200 found'};$bad=$false;try{Initialize-StationConnections -Gateway 'TEST1/WX' -OwnRoomId '12345' -Ops $ops}catch{$bad=$true};Check $bad 'ambiguous HRI is not guessed'
 $ops.Physical={'COM3'};$bad=$false;try{Initialize-StationConnections -Gateway '' -OwnRoomId '12345' -Ops $ops}catch{$bad=$true};Check ($bad -and $script:events.Count -eq 0) 'identity validated before installation'
 $script:Root=Join-Path $script:Root 'restart-retry';$script:inventory=@();$script:events.Clear();$ops.Healthy={param($pair)$false}
 try{Initialize-StationConnections -Gateway 'TEST1/WX' -OwnRoomId '12345' -Ops $ops|Out-Null}catch{}
 $ops.Healthy={param($pair)$true};$recovered=Initialize-StationConnections -Gateway 'TEST1/WX' -OwnRoomId '12345' -Ops $ops
 Check ($recovered.NativePort -ceq 'COM12' -and @($script:events|Where-Object {$_ -ceq 'Create'}).Count -eq 1) 'retry after blocked load or restart reuses only the recorded owned pair'
 $target=Join-Path $fixtureRoot 'junction-target';New-Item -ItemType Directory $target|Out-Null
 $link=Join-Path $fixtureRoot 'junction';New-Item -ItemType Junction -Path $link -Target $target|Out-Null
 $script:Root=$link;$script:events.Clear();$ops.Installed={$false};$bad=$false
 try{Initialize-StationConnections -Gateway 'TEST1/WX' -OwnRoomId '12345' -Ops $ops|Out-Null}catch{$bad=$true}
 Check ($bad -and $script:events.Count -eq 0) 'linked data root is refused before driver or file mutation'
 Write-Output ('RESULT: '+$checks+' first-run checks passed; injected driver actions, real isolated persistence; no driver installed')
}finally{if($link -and (Test-Path -LiteralPath $link)){[IO.Directory]::Delete($link)};if(Test-Path $fixtureRoot){Remove-Item $fixtureRoot -Recurse -Force}}
