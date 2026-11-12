param([string]$Bin)
$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$module=Join-Path $Bin 'InstallerGuard.ps1';if(!(Test-Path $module)){throw 'Active-installation protection is not implemented'}
. $module
$target=Join-Path $env:LOCALAPPDATA 'M5LEE\synthetic-install';$passed=0
function Check($ok,$message){if(!$ok){throw $message};$script:passed++}
Assert-BridgeInstallIdle $target @();$passed++
$threw=$false;try{Assert-BridgeInstallIdle $target @(@{ExecutablePath=(Join-Path $target 'Bridge.exe');CommandLine=''})}catch{$threw=$true};Check $threw 'Open status app must block upgrade and uninstall'
$threw=$false;try{Assert-BridgeInstallIdle $target @(@{ExecutablePath='powershell.exe';CommandLine=('-NoProfile -File "'+$target+'\voice-adapter.ps1" -UntilStopped')})}catch{$threw=$true};Check $threw 'Running installed adapter must block file replacement'
Assert-BridgeInstallIdle $target @(@{ExecutablePath='powershell.exe';CommandLine=('-File "'+$target+'-other\voice-adapter.ps1"')});$passed++
Assert-BridgeInstallIdle $target @(@{ExecutablePath=(Join-Path ($target+'-other') 'Bridge.exe');CommandLine=''});$passed++
@{Pass=$true;Assertions=$passed;ActualProcessesStopped=$false;SyntheticProcessDiscovery=$true}|ConvertTo-Json -Compress
