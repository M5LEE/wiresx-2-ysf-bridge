# Copyright (c) 2026 M5LEE.
# SPDX-License-Identifier: GPL-3.0-or-later
param([string]$TargetDir=$PSScriptRoot,[ValidateSet('Install','Uninstall')][string]$Action='Install')
$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
function Assert-BridgeInstallIdle([string]$TargetDir,$Processes){
 $target=[IO.Path]::GetFullPath($TargetDir).TrimEnd('\');$exe=Join-Path $target 'Bridge.exe'
 foreach($p in @($Processes)){
  if($p.ExecutablePath -and $p.ExecutablePath -ieq $exe){throw 'Close the bridge status app using its tray Exit command before upgrading or uninstalling.'}
  foreach($name in @('BridgeSupervisor.ps1','voice-adapter.ps1','capture-startup-adapter.ps1','observe-room-extended.ps1')){
   $pattern='(?i)(?:^|\s)-File\s+"?'+[regex]::Escape((Join-Path $target $name))+'(?:"|\s|$)'
   if($p.CommandLine -and $p.CommandLine -match $pattern){throw 'Stop this installed bridge and wait for cleanup before upgrading or uninstalling. No running session was changed.'}
  }
 }
}
function Invoke-BridgeInstallerGuard([string]$TargetDir,[string]$Action){
 $operation=$Action
 $target=[IO.Path]::GetFullPath($TargetDir).TrimEnd('\')
 $processes=@(Get-CimInstance Win32_Process -Filter "Name='Bridge.exe' OR Name='powershell.exe' OR Name='pwsh.exe'")
 Assert-BridgeInstallIdle $target $processes
 if($Action -ceq 'Uninstall'){
  . (Join-Path $PSScriptRoot 'StartupIntegration.ps1');$script:Bin=$target
  $path=Join-Path $script:Root 'private-baseline\sign-in-startup.json';$j=Read-StartupJournal $path
  $svc=New-Object -ComObject Schedule.Service;$svc.Connect();$sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
  foreach($task in $svc.GetFolder('\').GetTasks(1)){
   $d=$task.Definition
   if($d.RegistrationInfo.Description -ceq $script:StartupMarker -and $d.Actions.Count -eq 1 -and $d.Actions.Item(1).Path -ieq (Join-Path $target 'Bridge.exe') -and (Convert-StartupSid $d.Principal.UserId) -cne $sid){throw 'Sign in as the account that enabled bridge startup before uninstalling.'}
  }
  if(!$j -or $j.InstallExe -ieq (Join-Path $target 'Bridge.exe')){Disable-BridgeStartup|Out-Null}
 }
 return @{Pass=$true;Action=$operation;RunningSessionsUntouched=$true;PrivateStationDataRetained=$true}
}
if($MyInvocation.InvocationName -ne '.'){
 try{Invoke-BridgeInstallerGuard $TargetDir $Action|ConvertTo-Json -Compress;exit 0}catch{Write-Output $_.Exception.Message;exit 1}
}
