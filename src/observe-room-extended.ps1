param([string]$Tag,[ValidateRange(60,18060)][int]$Seconds=4500,[int]$AppPid,[string]$StartUtc,[switch]$UntilStopped)
$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
if($Tag -cnotmatch '^[A-Za-z0-9]+$' -or $AppPid -le 0){throw 'Explicit observation binding required'}
. (Join-Path $PSScriptRoot 'PublicRuntime.ps1')
$root=$script:Root;$station=Get-Station -RequireProfile
Assert-Binary 'BridgeProtocol.dll';[Reflection.Assembly]::LoadFrom((Join-Path $script:Bin 'BridgeProtocol.dll'))|Out-Null
$p=Get-Process -Id $AppPid
if($p.StartTime.ToUniversalTime().ToString('o') -cne $StartUtc -or (Get-FileHash $p.Path).Hash -ne '8F05DC26794144438566B880CE775F5178D62EB3C4DEB8C053089216342BC671'){throw 'Native binding mismatch'}
Add-Type -TypeDefinition @'
using System;using System.Text;using System.Runtime.InteropServices;
public static class OwnRoomRead {
 public delegate bool ChildProc(IntPtr h,IntPtr p);
 [DllImport("user32.dll")] public static extern int GetDlgCtrlID(IntPtr h);
 [DllImport("user32.dll",CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h,StringBuilder s,int n);
 [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr h,ChildProc callback,IntPtr p);
 [DllImport("user32.dll",EntryPoint="GetWindowLongW")] public static extern int GetWindowLong(IntPtr h,int index);
 [DllImport("user32.dll",CharSet=CharSet.Unicode)] public static extern IntPtr SendMessageTimeout(IntPtr h,uint message,UIntPtr count,StringBuilder text,uint flags,uint timeout,out UIntPtr result);
}
'@
$watch=[Diagnostics.Stopwatch]::StartNew();$tracker=[CumbriaCQ.Offline.RoomProofTracker]::new();$publicationFailures=0
while($UntilStopped -or $watch.Elapsed.TotalSeconds -lt $Seconds){
 $state=[pscustomobject]@{Tag=$Tag;AppPid=$AppPid;AppStartUtc=$StartUtc;Connected=$false;RoomId=$null;ConnectionKey=$null;RecoveryKey=$null;ControlId=1014;Method='NativeMainLog';ObserverPid=$PID;Utc=[DateTime]::UtcNow.ToString('o');Error=$null;ErrorDetail=$null;ErrorType=$null;PublicationFailures=$publicationFailures}
 $stage='NativeBinding';$view=$null
 try{
  $p=Get-Process -Id $AppPid
  if($p.StartTime.ToUniversalTime().ToString('o') -cne $StartUtc -or !$p.MainWindowHandle){throw 'Native binding unavailable'}
  $stage='NativeLogRead'
  $view=[CumbriaCQ.Offline.NativeLogTail]::ReadNative($p.MainWindowHandle)
  if($view.Partial){throw 'PartialNativeLogRead'}
  $tracker.Observe($view);$state.RoomId=$tracker.RoomId;$state.ConnectionKey=$tracker.ConnectionKey
  $state.Connected=($null -ne $state.RoomId)
 }catch{
  $state.Error=$stage;$errorBase=$_.Exception.GetBaseException();$state.ErrorType=$errorBase.GetType().Name
  $state.ErrorDetail=if($errorBase.Message -cin @('ReadTimeout','ReadRange','MissingWindow','DiagnosticControlUnavailable','LineRange','PartialNativeLogRead','IncompleteNativeLog','NativeLogShape')){$errorBase.Message}else{'UnclassifiedFailure'}
  if($stage -ceq 'NativeLogRead'){$state.RecoveryKey=$tracker.ConnectionKey}
 }finally{if($view){$view.Text=$null}}
 $path=Join-Path $root ('room-proof-'+$Tag+'.json')
 try{[CumbriaCQ.Offline.RoomProofFile]::Publish($path,($state|ConvertTo-Json -Compress))}catch{$publicationFailures++}
 # A temporary read failure closes forwarding but must not kill a healthy bridge.
 if(Test-Path (Join-Path $root ('observer-stop-'+$Tag+'.flag'))){break}
 Start-Sleep -Seconds 2
}
