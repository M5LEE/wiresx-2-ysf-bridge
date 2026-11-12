param([string]$Bin)
$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$module=Join-Path $Bin 'StartupIntegration.ps1'
if(!(Test-Path $module)){throw 'Sign-in startup integration is not implemented'}
. $module
$fixture=Join-Path $PSScriptRoot ('startup-fixture-'+[Guid]::NewGuid().ToString('N'));New-Item -ItemType Directory $fixture|Out-Null
$script:Root=$fixture;$passed=0
function Check($ok,$message){if(!$ok){throw $message};$script:passed++}
function New-Fixture {
 $f=Join-Path $fixture ([Guid]::NewGuid().ToString('N'));$startup=Join-Path $f 'startup';$private=Join-Path $f 'private';New-Item -ItemType Directory $startup,$private|Out-Null
 $original=Join-Path $startup 'YMLAN.lnk';[IO.File]::WriteAllText($original,'synthetic-shortcut')
 return @{Sid='S-1-5-21-100-200-300-1000';TaskName='M5LEE-WiresX2YSF-Test';InstallExe=(Join-Path $f 'Bridge.exe');NativeDir=(Join-Path $f 'native');Journal=(Join-Path $private 'startup.json');BackupDir=(Join-Path $private 'backup');StartupFolders=@($startup);Candidates=@(@{Original=$original;Target=(Join-Path $f 'native\YmLAN.exe')});BlockingEntries=@()}
}
$script:task=$null;$script:failCreate=$false;$script:calls=New-Object 'System.Collections.Generic.List[string]'
$ops=@{
 ReadTask={param($e)return $script:task}
 CreateTask={param($e)$script:calls.Add('Create');if(Test-Path $e.Candidates[0].Original){throw 'CompanionNotDisabledBeforeTask'};if(!(Test-Path $e.Journal)){throw 'IntentNotJournalled'};if($script:failCreate){throw 'SyntheticCreateFailure'};$script:task=@{Owned=$true;Executable=$e.InstallExe;Sid=$e.Sid;Arguments='--autostart';Enabled=$true}}
 DeleteTask={param($e)$script:calls.Add('Delete');$script:task=$null}
}
try {
 $e=New-Fixture;$before=(Get-FileHash $e.Candidates[0].Original).Hash
 $s=Get-BridgeStartupStatus -Environment $e -Ops $ops
 Check (!$s.Enabled -and (Test-Path $e.Candidates[0].Original) -and $script:calls.Count -eq 0) 'Status must be nonmutating'
 $s=Enable-BridgeStartup -Environment $e -Ops $ops
 Check ($s.Enabled -and !(Test-Path $e.Candidates[0].Original)) 'Enable must disable only selected companion shortcut'
 Check ($script:calls.Count -eq 1 -and $script:calls[0] -ceq 'Create') 'Enable creates task without running it'
 $s=Enable-BridgeStartup -Environment $e -Ops $ops
 Check ($s.Enabled -and $script:calls.Count -eq 1) 'Enable must be idempotent'
 $s=Disable-BridgeStartup -Environment $e -Ops $ops
 Check (!$s.Enabled -and (Get-FileHash $e.Candidates[0].Original).Hash -ceq $before -and !$script:task) 'Disable restores original shortcut and removes owned task'
 $s=Disable-BridgeStartup -Environment $e -Ops $ops
 Check (!$s.Enabled) 'Disable must be idempotent'
 $e=New-Fixture;$script:task=@{Owned=$false;Executable='foreign.exe';Sid=$e.Sid;Arguments='';Enabled=$true};$threw=$false
 try{Enable-BridgeStartup -Environment $e -Ops $ops|Out-Null}catch{$threw=$true}
 Check ($threw -and (Test-Path $e.Candidates[0].Original)) 'Foreign task collision must not alter startup'
 $script:task=$null;$script:failCreate=$true;$e=New-Fixture;$threw=$false
 try{Enable-BridgeStartup -Environment $e -Ops $ops|Out-Null}catch{$threw=$true}
 Check ($threw -and (Test-Path $e.Candidates[0].Original) -and !$script:task) 'Task failure must restore companion startup'
 $script:failCreate=$false;$e=New-Fixture;Enable-BridgeStartup -Environment $e -Ops $ops|Out-Null
 [IO.File]::WriteAllText($e.Candidates[0].Original,'replacement-owned-by-someone-else');$threw=$false
 try{Disable-BridgeStartup -Environment $e -Ops $ops|Out-Null}catch{$threw=$true}
 Check ($threw -and [IO.File]::ReadAllText($e.Candidates[0].Original) -ceq 'replacement-owned-by-someone-else' -and $script:task) 'Restore conflict must not clobber replacement or delete task'
 $script:task=$null;$e=New-Fixture;$e.BlockingEntries=@('SyntheticNativeRunEntry');$threw=$false
 try{Enable-BridgeStartup -Environment $e -Ops $ops|Out-Null}catch{$threw=$true}
 Check ($threw -and (Test-Path $e.Candidates[0].Original)) 'Unsupported competing native startup must fail closed'
 @{Pass=$true;Assertions=$passed;RealWindowsStartupChanged=$false;TaskBackendInjected=$true}|ConvertTo-Json -Compress
}finally{Remove-Item $fixture -Recurse -Force}
