# Copyright (c) 2026 M5LEE.
# SPDX-License-Identifier: GPL-3.0-or-later
param([ValidateSet('Status','Enable','Disable')][string]$Action='Status')
$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
. (Join-Path $PSScriptRoot 'PublicRuntime.ps1')
$script:StartupMarker='M5LEE WiresX 2 YSF Bridge sign-in startup v1'
function Read-StartupJournal($path){
 Assert-DataPath $path
 if(!(Test-Path -LiteralPath $path)){return $null}
 if((Get-Item -LiteralPath $path).Length -gt 65536){throw 'StartupJournalTooLarge'}
 return (Get-Content -LiteralPath $path -Raw|ConvertFrom-Json)
}
function Write-StartupJournal($e,$j){
 Assert-DataPath $e.Journal;$tmp=$e.Journal+'.pending'
 try{$j|ConvertTo-Json -Depth 7|Set-Content -LiteralPath $tmp -Encoding UTF8;if(Test-Path -LiteralPath $e.Journal){[IO.File]::Replace($tmp,$e.Journal,[NullString]::Value)}else{[IO.File]::Move($tmp,$e.Journal)}}finally{if(Test-Path -LiteralPath $tmp){Remove-Item -LiteralPath $tmp}}
}
function Convert-StartupSid([string]$value){
 if($value -match '^S-1-') {return ([Security.Principal.SecurityIdentifier]::new($value)).Value}
 return ([Security.Principal.NTAccount]::new($value)).Translate([Security.Principal.SecurityIdentifier]).Value
}
function Get-StartupEnvironment([switch]$ForEnable){
 $sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
 $journal=Join-Path $script:Root 'private-baseline\sign-in-startup.json';Assert-DataPath $journal
 $station=$null;try{$station=Get-Station -RequireProfile:$ForEnable}catch{if($ForEnable){throw}}
 $nativeDir=if($station){Split-Path $station.NativePath}else{$old=Read-StartupJournal $journal;if($old){$old.NativeDir}else{$null}}
 if($ForEnable){Assert-Binary 'Bridge.exe';Initialize-PrivateData}
 $folders=@([Environment]::GetFolderPath('Startup'),[Environment]::GetFolderPath('CommonStartup'))|Where-Object {$_}|Select-Object -Unique
 $candidates=@();$blocking=@()
 if($ForEnable){
  $shell=New-Object -ComObject WScript.Shell
  foreach($folder in $folders){foreach($f in @(Get-ChildItem -LiteralPath $folder -Filter '*.lnk' -File -ErrorAction SilentlyContinue)){
   $link=$shell.CreateShortcut($f.FullName);$target=[Environment]::ExpandEnvironmentVariables($link.TargetPath)
   if($target -and (Split-Path $target) -ieq $nativeDir -and [IO.Path]::GetFileName($target) -iin @('Wires-X.exe','YmLAN.exe')){
    if($f.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'LinkedStartupShortcutUnsupported'}
    $candidates+=@{Original=$f.FullName;Target=$target}
   }
  }}
  foreach($key in @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Run','HKLM:\Software\Microsoft\Windows\CurrentVersion\Run','HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run')){
   if(Test-Path $key){foreach($p in (Get-ItemProperty $key).PSObject.Properties){if($p.Name -notlike 'PS*' -and [Environment]::ExpandEnvironmentVariables([string]$p.Value).IndexOf($nativeDir,[StringComparison]::OrdinalIgnoreCase) -ge 0){$blocking+='Native Run entry: '+$p.Name}}}
  }
  $svc=New-Object -ComObject Schedule.Service;$svc.Connect()
  function Find-NativeStartupTasks($folder){
   foreach($t in $folder.GetTasks(1)){if(!$t.Enabled -or !$t.Definition.Triggers.Count){continue};foreach($a in $t.Definition.Actions){if($a.Type -eq 0 -and (Split-Path $a.Path) -ieq $nativeDir -and [IO.Path]::GetFileName($a.Path) -iin @('Wires-X.exe','YmLAN.exe')){Write-Output $t.Path}}}
   foreach($child in $folder.GetFolders(0)){Find-NativeStartupTasks $child}
  }
  $blocking+=@(Find-NativeStartupTasks ($svc.GetFolder('\'))|ForEach-Object {'Native scheduled startup: '+$_})
 }
 return @{Sid=$sid;TaskName=('M5LEE-WiresX2YSF-SignIn-'+$sid);InstallExe=(Join-Path $script:Bin 'Bridge.exe');NativeDir=$nativeDir;Journal=$journal;BackupDir=(Join-Path $script:Root 'private-baseline\startup-shortcuts');StartupFolders=@($folders);Candidates=@($candidates);BlockingEntries=@($blocking)}
}
function Get-StartupOps {
 return @{
  ReadTask={param($e)
   $svc=New-Object -ComObject Schedule.Service;$svc.Connect();$matches=@($svc.GetFolder('\').GetTasks(1)|Where-Object {$_.Name -ceq $e.TaskName});if(!$matches.Count){return $null};$t=$matches[0];$d=$t.Definition;$owned=$false;$exe='';$args='';$sid=''
   try{
    $sid=Convert-StartupSid $d.Principal.UserId
    if($d.Actions.Count -eq 1 -and $d.Triggers.Count -eq 1){$a=$d.Actions.Item(1);$tr=$d.Triggers.Item(1);$exe=$a.Path;$args=$a.Arguments
     $owned=$a.Type -eq 0 -and $exe -ieq $e.InstallExe -and $args -ceq '--autostart' -and $sid -ceq $e.Sid -and $d.Principal.LogonType -eq 3 -and $d.Principal.RunLevel -eq 1 -and $tr.Type -eq 9 -and (Convert-StartupSid $tr.UserId) -ceq $e.Sid -and $tr.Delay -ceq 'PT20S' -and $d.Settings.ExecutionTimeLimit -ceq 'PT0S' -and $d.Settings.MultipleInstances -eq 2 -and $d.RegistrationInfo.Description -ceq $script:StartupMarker
    }
   }catch{$owned=$false}
   return @{Owned=[bool]$owned;Executable=$exe;Sid=$sid;Arguments=$args;Enabled=[bool]$t.Enabled}
  }
  CreateTask={param($e)
   $svc=New-Object -ComObject Schedule.Service;$svc.Connect();$t=$svc.NewTask(0);$t.RegistrationInfo.Description=$script:StartupMarker;$t.Principal.UserId=$e.Sid;$t.Principal.LogonType=3;$t.Principal.RunLevel=1
   $t.Settings.Enabled=$true;$t.Settings.AllowDemandStart=$true;$t.Settings.ExecutionTimeLimit='PT0S';$t.Settings.MultipleInstances=2;$t.Settings.DisallowStartIfOnBatteries=$false;$t.Settings.StopIfGoingOnBatteries=$false;$t.Settings.StartWhenAvailable=$false
   $tr=$t.Triggers.Create(9);$tr.UserId=$e.Sid;$tr.Delay='PT20S';$tr.Enabled=$true;$a=$t.Actions.Create(0);$a.Path=$e.InstallExe;$a.Arguments='--autostart';$a.WorkingDirectory=Split-Path $e.InstallExe
   $null=$svc.GetFolder('\').RegisterTaskDefinition($e.TaskName,$t,2,$e.Sid,$null,3)
   # Register only: never Run the task here.
  }
  DeleteTask={param($e)$svc=New-Object -ComObject Schedule.Service;$svc.Connect();$svc.GetFolder('\').DeleteTask($e.TaskName,0)}
 }
}
function Assert-StartupTask($task,$e){
 if(!$task -or !$task.Owned -or $task.Executable -ine $e.InstallExe -or $task.Sid -cne $e.Sid -or $task.Arguments -cne '--autostart'){throw 'StartupTaskOwnershipMismatch'}
}
function Assert-StartupJournal($e,$j){
 if($j.Version -ne 1 -or $j.Sid -cne $e.Sid -or $j.TaskName -cne $e.TaskName -or ($j.State -cne 'Disabled' -and ($j.InstallExe -ine $e.InstallExe -or $j.NativeDir -ine $e.NativeDir)) -or @($j.Shortcuts).Count -gt 20){throw 'StartupJournalOwnershipMismatch'}
 foreach($r in @($j.Shortcuts)){
  if(@($e.StartupFolders|Where-Object {$_ -ieq (Split-Path $r.Original)}).Count -ne 1 -or [IO.Path]::GetExtension($r.Original) -ine '.lnk' -or (Split-Path $r.Backup) -ine $e.BackupDir -or $r.Hash -cnotmatch '^[A-F0-9]{64}$'){throw 'StartupJournalPathMismatch'}
  Assert-DataPath $r.Backup
 }
}
function Get-BridgeStartupStatus($Environment=$null,$Ops=$null){
 $e=if($Environment){$Environment}else{Get-StartupEnvironment};$ops=if($Ops){$Ops}else{Get-StartupOps};$j=Read-StartupJournal $e.Journal;$task=& $ops.ReadTask $e
 if(!$j){if($task){throw 'UnjournalledStartupTask'};return @{Enabled=$false;Message='Automatic sign-in startup is off.';State='Disabled'}}
 Assert-StartupJournal $e $j
 if($j.State -ceq 'Enabled'){
  Assert-StartupTask $task $e
  foreach($r in @($j.Shortcuts)){if(Test-Path -LiteralPath $r.Original){throw 'CompetingStartupShortcutReappeared'};if(!(Test-Path -LiteralPath $r.Backup) -or (Get-FileHash -LiteralPath $r.Backup).Hash -cne $r.Hash){throw 'StartupBackupChanged'}}
  return @{Enabled=[bool]$task.Enabled;Message='Start bridge and WIRES-X at Windows sign-in (20-second delay).';State=$(if($task.Enabled){'Enabled'}else{'TaskDisabled'})}
 }
 if($j.State -cne 'Disabled'){throw 'StartupRecoveryRequired'}
 if($task){throw 'UnexpectedStartupTask'}
 return @{Enabled=$false;Message='Automatic sign-in startup is off; original shortcuts restored.';State='Disabled'}
}
function Restore-StartupShortcuts($e,$j){
 # Preflight every restore before mutating anything, including removing the task.
 foreach($r in @($j.Shortcuts)){
  if(Test-Path -LiteralPath $r.Original){if((Get-FileHash -LiteralPath $r.Original).Hash -cne $r.Hash){throw 'StartupRestoreConflict'}}
  elseif(!(Test-Path -LiteralPath $r.Backup) -or (Get-FileHash -LiteralPath $r.Backup).Hash -cne $r.Hash){throw 'StartupBackupMissingOrChanged'}
 }
 foreach($r in @($j.Shortcuts)){
  if(!(Test-Path -LiteralPath $r.Original)){Move-Item -LiteralPath $r.Backup -Destination $r.Original}
  if((Get-FileHash -LiteralPath $r.Original).Hash -cne $r.Hash){throw 'StartupRestoreVerificationFailed'}
 }
}
function Enable-BridgeStartup($Environment=$null,$Ops=$null){
 $e=if($Environment){$Environment}else{Get-StartupEnvironment -ForEnable};$ops=if($Ops){$Ops}else{Get-StartupOps};Assert-DataPath $e.Journal;Assert-DataPath $e.BackupDir
 if(@($e.BlockingEntries).Count){throw ('CompetingNativeStartupRequiresManualReview: '+($e.BlockingEntries -join '; '))}
 $old=Read-StartupJournal $e.Journal
 if($old){Assert-StartupJournal $e $old;if($old.State -ceq 'Enabled'){return (Get-BridgeStartupStatus -Environment $e -Ops $ops)};if($old.State -cne 'Disabled'){throw 'StartupRecoveryRequired'}}
 if(& $ops.ReadTask $e){throw 'StartupTaskAlreadyExists'}
 if(@($e.Candidates).Count -gt 20){throw 'TooManyNativeStartupShortcuts'}
 New-Item -ItemType Directory -Force $e.BackupDir|Out-Null
 $records=@();foreach($r in @($e.Candidates)){
  if(@($e.StartupFolders|Where-Object {$_ -ieq (Split-Path $r.Original)}).Count -ne 1 -or (Split-Path $r.Target) -ine $e.NativeDir -or [IO.Path]::GetFileName($r.Target) -inotin @('Wires-X.exe','YmLAN.exe')){throw 'StartupShortcutScopeMismatch'}
  $item=Get-Item -LiteralPath $r.Original;if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'LinkedStartupShortcutUnsupported'}
  $records+=@{Original=$r.Original;Backup=(Join-Path $e.BackupDir ([Guid]::NewGuid().ToString('N')+'.lnk'));Hash=(Get-FileHash -LiteralPath $r.Original).Hash}
 }
 $j=@{Version=1;Sid=$e.Sid;TaskName=$e.TaskName;InstallExe=$e.InstallExe;NativeDir=$e.NativeDir;State='Preparing';Shortcuts=$records};Write-StartupJournal $e $j
 try{
  foreach($r in $records){if((Get-FileHash -LiteralPath $r.Original).Hash -cne $r.Hash){throw 'StartupShortcutChanged'};Move-Item -LiteralPath $r.Original -Destination $r.Backup;if((Get-FileHash -LiteralPath $r.Backup).Hash -cne $r.Hash){throw 'StartupBackupVerificationFailed'}}
  $j.State='TaskPending';Write-StartupJournal $e $j;& $ops.CreateTask $e
  $task=& $ops.ReadTask $e;Assert-StartupTask $task $e;if(!$task.Enabled){throw 'StartupTaskNotEnabled'}
  $j.State='Enabled';Write-StartupJournal $e $j;return (Get-BridgeStartupStatus -Environment $e -Ops $ops)
 }catch{
  $originalError=$_
  try{$task=& $ops.ReadTask $e;if($task){Assert-StartupTask $task $e;& $ops.DeleteTask $e};Restore-StartupShortcuts $e $j;$j.State='Disabled';Write-StartupJournal $e $j}catch{$j.State='RecoveryRequired';Write-StartupJournal $e $j;throw 'StartupEnableRollbackRequiresReview'}
  throw $originalError
 }
}
function Disable-BridgeStartup($Environment=$null,$Ops=$null){
 $e=if($Environment){$Environment}else{Get-StartupEnvironment};$ops=if($Ops){$Ops}else{Get-StartupOps};$j=Read-StartupJournal $e.Journal;$task=& $ops.ReadTask $e
 if(!$j){if($task){throw 'UnjournalledStartupTask'};return (Get-BridgeStartupStatus -Environment $e -Ops $ops)}
 Assert-StartupJournal $e $j
 if($j.State -ceq 'Disabled'){return (Get-BridgeStartupStatus -Environment $e -Ops $ops)}
 if($task){Assert-StartupTask $task $e}
 # Validate restoration first; leave both task and replacement untouched on conflict.
 foreach($r in @($j.Shortcuts)){if(Test-Path -LiteralPath $r.Original){if((Get-FileHash -LiteralPath $r.Original).Hash -cne $r.Hash){throw 'StartupRestoreConflict'}}elseif(!(Test-Path -LiteralPath $r.Backup) -or (Get-FileHash -LiteralPath $r.Backup).Hash -cne $r.Hash){throw 'StartupBackupMissingOrChanged'}}
 $j.State='Restoring';Write-StartupJournal $e $j
 if($task){& $ops.DeleteTask $e;if(& $ops.ReadTask $e){throw 'StartupTaskRemovalFailed'}}
 Restore-StartupShortcuts $e $j;$j.State='Disabled';Write-StartupJournal $e $j
 return (Get-BridgeStartupStatus -Environment $e -Ops $ops)
}
if($MyInvocation.InvocationName -ne '.'){
 $mutex=$null;$held=$false
 try{
  if($Action -ne 'Status'){$sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value;$mutex=[Threading.Mutex]::new($false,('Local\M5LEE.WiresX2YSF.Startup.'+$sid));$held=$mutex.WaitOne(0);if(!$held){throw 'AnotherStartupChangeIsInProgress'}}
  $result=switch($Action){'Enable'{Enable-BridgeStartup};'Disable'{Disable-BridgeStartup};default{Get-BridgeStartupStatus}};$result|ConvertTo-Json -Compress;exit 0
 }catch{@{Enabled=$false;State='Error';Message=$_.Exception.Message}|ConvertTo-Json -Compress;exit 1}finally{if($held){$mutex.ReleaseMutex()};if($mutex){$mutex.Dispose()}}
}
