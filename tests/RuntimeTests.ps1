param([string]$Bin)
$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
. (Join-Path $Bin 'PublicRuntime.ps1')
$script:Bin=$Bin;$script:Root=Join-Path (Split-Path $Bin) ('tests\runtime-'+[Guid]::NewGuid().ToString('N'))
$checks=0
function Check($condition,$name){if(!$condition){throw ('FAIL: '+$name)};$script:checks++;Write-Output ('PASS: '+$name)}
function Refuses($action,$name){$bad=$false;try{& $action|Out-Null}catch{$bad=$true};Check $bad $name}
try{
 Refuses {Get-Station -RequireProfile} 'fresh installation cannot use somebody else station'
 Refuses {Assert-DataPath 'C:\Windows\not-station-data'} 'runtime writes cannot target paths outside station data'
 $s=[pscustomobject]@{SchemaVersion=1;Gateway='TEST1/WX';OwnRoomId='12345';PhysicalPort='COM101';NativePort='COM102';AdapterPort='COM103';NativePath='C:\Program Files (x86)\YAESUMUSEN\WIRES-X\Wires-X.exe';RadioProfileSha256=''}
 Save-Station $s;Check ((Get-Station).OwnRoomId -ceq '12345') 'exact operator room survives save'
 Refuses {Get-Station -RequireProfile} 'voice startup refuses missing owned radio metadata'
 $s.OwnRoomId='1234';Refuses {Save-Station $s} 'short room ID is rejected rather than padded';$s.OwnRoomId='12345'
 $s.AdapterPort='COM101';Refuses {Save-Station $s} 'same physical and virtual port refused';$s.AdapterPort='COM103'
 $s.Gateway='';Refuses {Save-Station $s} 'blank gateway identity refused';$s.Gateway='TEST1/WX'
 Check ((Get-Station).Gateway -ceq 'TEST1/WX') 'failed validation does not corrupt saved station'
 $query='D1M0045'+'7000'+(('433.00000+000.00000'+('0'*13))*2)+'F';$reply=$query.Substring(0,7)+'5000'+$query.Substring(11,64)+'0'
 $rows=@(@{Direction='ClientToHri';Body=$query},@{Direction='HriToClient';Body=$reply},@{Direction='HriToClient';Body='D1V0001X'},@{Direction='HriToClient';Body='D1C000B00005TEST10'},@{Direction='HriToClient';Body='D1P000B00005TEST10'},@{Direction='HriToClient';Body='D1B00010'},@{Direction='HriToClient';Body='B0 0    0000000'})
 $input=Join-Path $script:Root 'synthetic-input.json';$capture=@{VoiceStored=$false;HriIdentityStored=$false;Records=$rows};$capture|ConvertTo-Json -Depth 6|Set-Content $input
 Import-OwnProfile $input;$own=Get-Station -RequireProfile
 Check ($own.RadioProfileSha256 -cmatch '^[A-F0-9]{64}$') 'synthetic owned metadata is validated and hash bound'
 Check ((Get-Acl (Join-Path $script:Root 'private-baseline')).AreAccessRulesProtected) 'private metadata inheritance removed'
 $hash=$own.RadioProfileSha256;$capture.Records+=@{Direction='HriToClient';Body='D1R00892BAD'};$capture|ConvertTo-Json -Depth 6|Set-Content $input
 Refuses {Import-OwnProfile $input} 'voice payload cannot be imported as startup metadata'
 Check ((Get-Station -RequireProfile).RadioProfileSha256 -ceq $hash) 'rejected import preserves valid private profile'
 $own.RadioProfileSha256='0'*64;Save-Station $own;Refuses {Get-Station -RequireProfile} 'changed metadata pin refuses startup'
 function global:Get-CimInstance {param($ClassName,$Filter);return $global:TestProcesses}
 try{
  $global:TestProcesses=@([pscustomobject]@{ProcessId=100;CommandLine='powershell.exe -File "C:\Example\voice-adapter.ps1"'})
  Check (@(Find-BridgeAdapters).Count -eq 1) 'global detection finds an existing bridge from another folder'
  $encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes("& 'C:\Example\capture-startup-adapter.ps1'"))
  $global:TestProcesses=@([pscustomobject]@{ProcessId=101;CommandLine=('powershell.exe -EncodedCommand '+$encoded)})
  Check (@(Find-BridgeAdapters).Count -eq 1) 'encoded metadata capture is not missed by duplicate detection'
  $global:TestProcesses=@([pscustomobject]@{ProcessId=102;CommandLine=$null})
  Refuses {Find-BridgeAdapters} 'unreadable process metadata fails closed'
 }finally{Remove-Item Function:\Get-CimInstance;Remove-Variable TestProcesses -Scope Global}
 $tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $Bin 'BridgeSupervisor.ps1'),[ref]$tokens,[ref]$errors)
 foreach($fn in $ast.FindAll({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -in @('Load-Aliases','Invoke-Lifecycle')},$true)){Invoke-Expression $fn.Extent.Text}
 $script:Station=Get-Station
 @(@{Path='HKLM:\SYSTEM\CurrentControlSet\Enum\USB\Fixture\A';FriendlyName='HRI-200 Communication device A (COM101)'},@{Path='HKLM:\SYSTEM\CurrentControlSet\Enum\COM0COM\PORT\CNCA0';FriendlyName='com0com - serial port emulator (COM102)'})|ConvertTo-Json|Set-Content (Join-Path $script:Root 'discovery-name-backup.json')
 function global:Get-ItemProperty {param($LiteralPath,$Name);if($LiteralPath -like '*\COM0COM\*'){return @{FriendlyName='com0com - serial port emulator (COM102)'}};return @{FriendlyName='HRI-200 Communication device A (COM101)'}}
 try{$aliases=Load-Aliases;Check ($aliases.Count -eq 2 -and @($aliases|Where-Object {$_.Alias -ceq 'HRI-200 Communication device A (COM102)'}).Count -eq 1) 'discovery alias mapping uses operator COM ports, not development-machine ports'}finally{Remove-Item Function:\Get-ItemProperty}
 $script:events=New-Object 'System.Collections.Generic.List[string]';$Capture=$false
 $ops=@{Preflight={$script:events.Add('preflight')};Prepare={$script:events.Add('prepare')};Adapter={$script:events.Add('adapter')};Alive={$true};Ready={$script:events.Add('ready');$true};Native={$script:events.Add('native')};Observer={$script:events.Add('observer')};Healthy={$true};Stop={$false};Tick={};Cleanup={$script:events.Add('cleanup')}}
 $outcome=Invoke-Lifecycle $ops 1 1
 Check (($script:events -join ',') -ceq 'preflight,prepare,adapter,ready,native,observer,cleanup' -and $outcome -ceq 'RuntimeExpired') 'public lifecycle preserves adapter-first ordering and finite cleanup'
 Write-Output ('RESULT: '+$checks+' public runtime checks passed; synthetic data only; no hardware or native operations')
}finally{if(Test-Path $script:Root){Remove-Item -LiteralPath $script:Root -Recurse -Force}}
