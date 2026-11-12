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
$watch=[Diagnostics.Stopwatch]::StartNew();$lastConnectionLine=''
while($UntilStopped -or $watch.Elapsed.TotalSeconds -lt $Seconds){
 $state=[pscustomobject]@{Tag=$Tag;AppPid=$AppPid;Connected=$false;RoomId=$null;ControlId=1014;Method='NativeMainLog';ObserverPid=$PID;Utc=[DateTime]::UtcNow.ToString('o');Error=$null}
 try{
  $p=Get-Process -Id $AppPid
  if($p.StartTime.ToUniversalTime().ToString('o') -cne $StartUtc -or !$p.MainWindowHandle){throw 'Native binding unavailable'}
  $view=[CumbriaCQ.Offline.NativeLogTail]::ReadNative($p.MainWindowHandle)
  if($view.Partial){throw 'PartialNativeLogRead'}
  $logText=$lastConnectionLine+$view.Text
  $state.RoomId=[CumbriaCQ.Offline.RoomLog]::CurrentRoom($logText)
  $state|Add-Member NoteProperty AppStartUtc $StartUtc
  $state|Add-Member NoteProperty ConnectionKey ([CumbriaCQ.Offline.RoomLog]::ConnectionKey($logText))
  $lastConnectionLine=if($state.RoomId){$state.ConnectionKey.Split('|')[0]+' Connected to CURRENT('+$state.RoomId+").`n"}else{''}
  $state.Connected=($null -ne $state.RoomId);$view.Text=$null
 }catch{$state.Error=$_.Exception.GetType().Name}
 $path=Join-Path $root ('room-proof-'+$Tag+'.json');$temp=$path+'.extended-pending'
 try{$state|ConvertTo-Json -Compress|Set-Content $temp;Move-Item -Force $temp $path}
 catch{Remove-Item $temp -Force -ErrorAction SilentlyContinue}
 # A temporary read failure closes forwarding but must not kill a healthy bridge.
 if(Test-Path (Join-Path $root ('observer-stop-'+$Tag+'.flag'))){break}
 Start-Sleep -Seconds 2
}
