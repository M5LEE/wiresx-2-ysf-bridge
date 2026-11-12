# Copyright (c) 2026 M5LEE. MIT; see LICENSE.
param([switch]$Watch)
$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
function Get-BridgeDisplayState($s){
 $code='Stopped';$message='Ready to start. Keep the FTM off; WIRES-X login can take several minutes.';$room=$null;$canStart=$false;$canStop=$false
 if($s.ExistingBridge -and !$s.OwnLive){$code='OtherSession';$message='Another bridge installation is running. Start and Stop are disabled here.'}
 elseif($s.OwnerPresent -and !$s.OwnLive){$code='NeedsAttention';$message='An ownership record remains. Inspect cleanup before starting again.'}
 elseif($s.OwnLive){
  $canStop=$true
  if($s.OwnerState -cne 'Running'){$code='Starting';$message='Starting the bridge adapter and WIRES-X. Please wait.'}
  elseif(!$s.ProgressFresh){$code='Degraded';$message='Bridge processes are present, but their status is stale. Check diagnostics.'}
  elseif(!$s.Configured){$code='Starting';$message='Waiting for the WIRES-X transceiver handshake.'}
  elseif(!$s.ProofFresh -or !$s.Connected){$code='Connecting';$message='Waiting for a WIRES-X room connection. Login can take several minutes.'}
  elseif(!$s.LinkHealthy){$code='Degraded';$message='WIRES-X is connected, but the YSF link is unavailable.';$room=$s.RoomId}
  else{$code='Running';$message='Bridge running. WIRES-X room connected and YSF link healthy.';$room=$s.RoomId}
 }elseif(!$s.SetupReady){$code='SetupRequired';$message='Complete station setup and validate your radio profile before starting.'}
 elseif($s.Fault){$code='Error';$message='Bridge stopped after a fault. Check diagnostics before restarting.';$canStart=$true}
 else{$canStart=$true}
 return @{Code=$code;Summary=$message;Room=$room;CanStart=$canStart;CanStop=$canStop}
}
function Read-BridgeStatusJson($path){
 Assert-DataPath $path;if(!(Test-Path -LiteralPath $path)){return $null}
 $f=[IO.File]::Open($path,[IO.FileMode]::Open,[IO.FileAccess]::Read,([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
 $reader=[IO.StreamReader]::new($f);try{if($f.Length -gt 1048576){throw 'StatusFileTooLarge'};return ($reader.ReadToEnd()|ConvertFrom-Json)}finally{$reader.Dispose()}
}
function Get-CurrentBridgeStatus {
 . (Join-Path $PSScriptRoot 'PublicRuntime.ps1')
 $setup=$false;$station=$null;try{$station=Get-Station -RequireProfile;$setup=(Get-FileHash $station.NativePath).Hash -ceq $script:SupportedNativeHash}catch{}
 $adapters=@(Find-BridgeAdapters);$owner=Read-BridgeStatusJson (Join-Path $script:Root 'launcher-state\owner.json');$own=$false;$progress=$null;$proof=$null;$progressFresh=$false;$proofFresh=$false;$fault=$null
 if($owner -and $owner.Root -ceq $script:Root -and $owner.Tag -cmatch '^bridge[a-f0-9]{32}$'){
  $own=$true
  foreach($kind in @('Supervisor','Adapter','Native','Observer')){
   $id=$owner.$kind
   if(!$id){if($owner.State -ceq 'Starting'){continue};$own=$false;break}
   $p=Get-Process -Id $id.Pid -ErrorAction SilentlyContinue
   if(!$p -or $id.Root -cne $script:Root -or $id.Tag -cne $owner.Tag -or $p.StartTime.ToUniversalTime().ToString('o') -cne $id.Created){$own=$false;break}
   if($kind -ne 'Native'){
    $line=(Get-CimInstance Win32_Process -Filter ('ProcessId='+$p.Id)).CommandLine
    $name=switch($kind){'Supervisor'{'BridgeSupervisor.ps1'};'Adapter'{'voice-adapter.ps1'};'Observer'{'observe-room-extended.ps1'}}
    if(!$line -or !$line.Contains((Join-Path $script:Bin $name))){$own=$false;break}
   }elseif(!$station -or $p.Path -ine $station.NativePath){$own=$false;break}
  }
  if($own){
   $path=Join-Path $script:Root ('progress-'+$owner.Tag+'.json');$progress=Read-BridgeStatusJson $path
   if($progress -and $progress.Tag -ceq $owner.Tag){$age=([DateTime]::UtcNow-(Get-Item $path).LastWriteTimeUtc).TotalSeconds;$progressFresh=$age -ge -2 -and $age -le 10}
   $proof=Read-BridgeStatusJson (Join-Path $script:Root ('room-proof-'+$owner.Tag+'.json'))
   if($proof){$age=([DateTime]::UtcNow-[DateTime]::Parse($proof.Utc).ToUniversalTime()).TotalSeconds;$proofFresh=$age -ge -2 -and $age -le 10 -and $proof.Tag -ceq $owner.Tag -and $proof.AppPid -eq $owner.Native.Pid -and $proof.AppStartUtc -ceq $owner.Native.Created -and !$proof.Error -and $proof.Method -ceq 'NativeMainLog' -and $proof.ControlId -eq 1014 -and $proof.RoomId -cmatch '^[0-9]{5}$' -and $proof.RoomId -cne '00000'}
  }
 }elseif(!$owner){
  $last=Get-ChildItem -LiteralPath $script:Root -Filter 'adapter-bridge*-result.json' -File -ErrorAction SilentlyContinue|Where-Object {$_.Name -cmatch '^adapter-bridge[a-f0-9]{32}-result\.json$'}|Sort-Object LastWriteTimeUtc -Descending|Select-Object -First 1
  if($last){$result=Read-BridgeStatusJson $last.FullName;if($result.Error){$fault='AdapterFault'}}
 }
 $snapshot=@{ExistingBridge=($adapters.Count -gt 0);OwnerPresent=($null -ne $owner);OwnLive=$own;OwnerState=$owner.State;SetupReady=$setup;Configured=[bool]$progress.Configured;ProgressFresh=$progressFresh;ProofFresh=$proofFresh;Connected=[bool]$proof.Connected;RoomId=$proof.RoomId;LinkHealthy=[bool]$progress.LinkHealthy;Fault=$fault}
 $view=Get-BridgeDisplayState $snapshot
 $ysf='Not configured';try{Assert-Binary 'BridgeConfigCore.dll';[Reflection.Assembly]::LoadFrom((Join-Path $script:Bin 'BridgeConfigCore.dll'))|Out-Null;$settings=[CumbriaCQ.Configuration.SettingsStore]::Open((Join-Path $script:Root 'bridge-config.json')).Settings;$ysf=$settings.YsfRoomId+' '+$settings.YsfRoomName}catch{}
 . (Join-Path $PSScriptRoot 'StartupIntegration.ps1')
 $startup=@{Enabled=$false;State='Error';Message='Startup status unavailable.'};try{$startup=Get-BridgeStartupStatus}catch{$startup.Message=$_.Exception.Message}
 return @{Event='Check';Data=@{StatusCode=$view.Code;Summary=$view.Summary;NativeRoom=$view.Room;YsfDestination=$ysf;CanStart=$view.CanStart;CanStop=$view.CanStop;ExistingBridge=$snapshot.ExistingBridge;OwnerManifestPresent=$snapshot.OwnerPresent;SetupReady=$setup;OwnLive=$own;StartupEnabled=$startup.Enabled;StartupState=$startup.State;StartupMessage=$startup.Message;CheckedUtc=[DateTime]::UtcNow.ToString('o');NonInvasive=$true}}
}
function Get-BridgeStatusResponse {
 try{return (Get-CurrentBridgeStatus|ConvertTo-Json -Depth 4 -Compress)}catch{return (@{Event='Check';Data=@{StatusCode='Error';Summary='Unable to verify bridge status. Run the launcher as administrator and check diagnostics.';CanStart=$false;CanStop=$false;StartupEnabled=$false;StartupState='Error';StartupMessage=$_.Exception.Message}}|ConvertTo-Json -Depth 3 -Compress)}
}
if($MyInvocation.InvocationName -ne '.'){
 if($Watch){
  # Reuse only the helper process, never a cached status/ownership decision.
  [Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)
  while(($request=[Console]::ReadLine()) -ne $null){if($request -cne 'CHECK'){throw 'UnexpectedStatusRequest'};[Console]::WriteLine((Get-BridgeStatusResponse))}
  exit 0
 }
 $response=Get-BridgeStatusResponse;$response
 if(($response|ConvertFrom-Json).Data.StatusCode -ceq 'Error'){exit 1};exit 0
}
