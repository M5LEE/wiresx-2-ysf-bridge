param([string]$Tag,[ValidateRange(60,18060)][int]$Seconds=4500,[int]$AppPid,[string]$StartUtc)
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
$watch=[Diagnostics.Stopwatch]::StartNew()
while($watch.Elapsed.TotalSeconds -lt $Seconds){
 $state=[pscustomobject]@{Tag=$Tag;AppPid=$AppPid;Connected=$false;RoomId=$null;ControlId=1014;Method='NativeMainLog';ObserverPid=$PID;Utc=[DateTime]::UtcNow.ToString('o');Error=$null}
 try{
  $p=Get-Process -Id $AppPid
  if($p.StartTime.ToUniversalTime().ToString('o') -cne $StartUtc -or !$p.MainWindowHandle){throw 'Native binding unavailable'}
  $text=New-Object Text.StringBuilder 131072
  $callback=[OwnRoomRead+ChildProc]{param($h,$unused)
   if([OwnRoomRead]::GetDlgCtrlID($h) -eq 1014){
    $name=New-Object Text.StringBuilder 64;$null=[OwnRoomRead]::GetClassName($h,$name,64)
    if($name.ToString() -eq 'Edit' -and (([OwnRoomRead]::GetWindowLong($h,-16) -band 32) -eq 0)){
     $result=[UIntPtr]::Zero;$null=[OwnRoomRead]::SendMessageTimeout($h,13,[UIntPtr]::new([uint32]131072),$text,2,500,[ref]$result)
    }
   };return $true
  }
  $null=[OwnRoomRead]::EnumChildWindows($p.MainWindowHandle,$callback,[IntPtr]::Zero)
  $state.Connected=[CumbriaCQ.Offline.RoomLog]::IsConnected($text.ToString(),$station.OwnRoomId)
  if($state.Connected){$state.RoomId=$station.OwnRoomId}
 }catch{$state.Error=$_.Exception.GetType().Name}
 $path=Join-Path $root ('room-proof-'+$Tag+'.json');$temp=$path+'.extended-pending'
 try{$state|ConvertTo-Json -Compress|Set-Content $temp;Move-Item -Force $temp $path}
 catch{Remove-Item $temp -Force -ErrorAction SilentlyContinue}
 if($state.Error -or (Test-Path (Join-Path $root ('observer-stop-'+$Tag+'.flag')))){break}
 Start-Sleep -Seconds 2
}
