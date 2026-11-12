param([string]$Bin)
$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$module=Join-Path $Bin 'BridgeStatus.ps1';if(!(Test-Path $module)){throw 'Readable bridge status is not implemented'}
. $module
$script:passed=0
function Check($ok,$message){if(!$ok){throw $message};$script:passed++}
$s=@{ExistingBridge=$true;OwnerPresent=$true;OwnLive=$true;OwnerState='Running';SetupReady=$true;Configured=$true;ProgressFresh=$true;ProofFresh=$true;Connected=$true;RoomId='12345';LinkHealthy=$true;Fault=$null}
$r=Get-BridgeDisplayState $s
Check ($r.Code -ceq 'Running' -and $r.CanStop -and !$r.CanStart -and $r.Room -ceq '12345') 'Running requires fresh native proof, healthy link and live ownership'
$s.ProofFresh=$false;$r=Get-BridgeDisplayState $s;Check ($r.Code -ceq 'Connecting' -and !$r.Room) 'Stale room proof must not show a connected room'
$s.ProofFresh=$true;$s.LinkHealthy=$false;$r=Get-BridgeDisplayState $s;Check ($r.Code -ceq 'Degraded') 'Reflector failure must not show green running status'
$s.LinkHealthy=$true;$s.ProgressFresh=$false;$r=Get-BridgeDisplayState $s;Check ($r.Code -ceq 'Degraded') 'Stale progress must not show green running status'
$s.OwnLive=$false;$r=Get-BridgeDisplayState $s;Check ($r.Code -ceq 'OtherSession' -and !$r.CanStart -and !$r.CanStop) 'Other installation must not be controllable'
$s.ExistingBridge=$false;$r=Get-BridgeDisplayState $s;Check ($r.Code -ceq 'NeedsAttention' -and !$r.CanStart) 'Retained owner must block another start'
$s.OwnerPresent=$false;$r=Get-BridgeDisplayState $s;Check ($r.Code -ceq 'Stopped' -and $r.CanStart -and !$r.CanStop) 'Stopped and ready status must permit manual start'
$s.SetupReady=$false;$r=Get-BridgeDisplayState $s;Check ($r.Code -ceq 'SetupRequired' -and !$r.CanStart) 'Unprepared station must not auto-start'
$s.SetupReady=$true;$s.Fault='Synthetic fault';$r=Get-BridgeDisplayState $s;Check ($r.Code -ceq 'Error' -and !$r.CanStop) 'Stopped adapter fault must remain visible'
@{Pass=$true;Assertions=$passed;HardwareTouched=$false;SyntheticSnapshotsOnly=$true}|ConvertTo-Json -Compress
