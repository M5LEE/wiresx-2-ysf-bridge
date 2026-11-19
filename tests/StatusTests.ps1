param([string]$Bin)
$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$module=Join-Path $Bin 'BridgeStatus.ps1';if(!(Test-Path $module)){throw 'Readable bridge status is not implemented'}
. $module
$script:passed=0
function Check($ok,$message){if(!$ok){throw $message};$script:passed++}
$s=@{ExistingBridge=$true;OwnerPresent=$true;OwnLive=$true;OwnerState='Running';SetupReady=$true;Configured=$true;ProgressFresh=$true;ProofFresh=$true;Connected=$true;RoomId='12345';LinkHealthy=$true;Fault=$null}
$r=Get-BridgeDisplayState $s
Check ($r.Code -ceq 'Running' -and $r.CanStop -and !$r.CanStart -and $r.Room -ceq '12345') 'Running requires fresh native proof, healthy link and live ownership'
Check ($r.NextStep -match 'No action') 'healthy status gives a clear next step'
$s.ProofFresh=$false;$r=Get-BridgeDisplayState $s;Check ($r.Code -ceq 'Connecting' -and !$r.Room) 'Stale room proof must not show a connected room'
$s.ProofFresh=$true;$s.LinkHealthy=$false;$r=Get-BridgeDisplayState $s;Check ($r.Code -ceq 'Degraded') 'Reflector failure must not show green running status'
Check ($r.NextStep -match 'Internet' -and $r.NextStep -match 'YSF room') 'YSF failure recommends targeted checks'
$s.LinkHealthy=$true;$s.ProgressFresh=$false;$r=Get-BridgeDisplayState $s;Check ($r.Code -ceq 'Degraded') 'Stale progress must not show green running status'
Check ($r.NextStep -match 'Check status' -and $r.NextStep -notmatch 'reinstall') 'stale status recommends a recheck rather than reinstalling'
$s.OwnLive=$false;$r=Get-BridgeDisplayState $s;Check ($r.Code -ceq 'OtherSession' -and !$r.CanStart -and !$r.CanStop) 'Other installation must not be controllable'
$s.ExistingBridge=$false;$r=Get-BridgeDisplayState $s;Check ($r.Code -ceq 'NeedsAttention' -and !$r.CanStart) 'Retained owner must block another start'
Check ($r.CanRecover -and $r.Summary -match 'Close WIRES-X' -and $r.Summary -match 'Recover') 'Interrupted session must offer explicit recovery and a plain-language next step'
Check ($r.NextStep -match 'Recover session' -and $r.NextStep -match '3. Start bridge') 'interrupted session explains the full recovery sequence'
$s.OwnerPresent=$false;$r=Get-BridgeDisplayState $s;Check ($r.Code -ceq 'Stopped' -and $r.CanStart -and !$r.CanStop) 'Stopped and ready status must permit manual start'
$s.SetupReady=$false;$r=Get-BridgeDisplayState $s;Check ($r.Code -ceq 'SetupRequired' -and !$r.CanStart) 'Unprepared station must not auto-start'
$s.SetupReady=$true;$s.Fault='Synthetic fault';$r=Get-BridgeDisplayState $s;Check ($r.Code -ceq 'Error' -and !$r.CanStop) 'Stopped adapter fault must remain visible'
if(!(Get-Command Get-BridgeYsfDestination -ErrorAction SilentlyContinue)){Write-Output 'Launcher must display the active YSF destination rather than only the saved target';exit 1}
$saved=[pscustomobject]@{YsfRoomId='00016';YsfRoomName='NEW'};$active=[pscustomobject]@{YsfActive=[pscustomobject]@{YsfRoomId='23534';YsfRoomName='OLD'}}
Check ((Get-BridgeYsfDestination $true $true $active $saved) -ceq '23534 OLD') 'A running bridge must display its reported active target, not the saved target'
Check ((Get-BridgeYsfDestination $true $false $active $saved) -notmatch '00016|23534') 'Stale progress must not assert an active YSF room'
Check ((Get-BridgeYsfDestination $false $false $null $saved) -ceq '00016 NEW (saved)') 'A stopped bridge may show the saved target explicitly'
@{Pass=$true;Assertions=$passed;HardwareTouched=$false;SyntheticSnapshotsOnly=$true}|ConvertTo-Json -Compress
