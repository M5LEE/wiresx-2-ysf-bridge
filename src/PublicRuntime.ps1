# Copyright (c) 2026 M5LEE. No vendor software or identities included.
# SPDX-License-Identifier: GPL-3.0-or-later
$script:Bin=$PSScriptRoot
$script:Root=Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'M5LEE\WIRESX-to-YSF-Brtidge'
$script:SupportedNativeHash='8F05DC26794144438566B880CE775F5178D62EB3C4DEB8C053089216342BC671'
function Assert-DataPath([string]$path){
 $base=[IO.Path]::GetFullPath($script:Root).TrimEnd('\');$full=[IO.Path]::GetFullPath($path)
 if($full -ine $base -and !$full.StartsWith($base+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'DataPathOutsideStationRoot'}
 $cursor=$full
 while($cursor){$item=Get-Item -LiteralPath $cursor -Force -ErrorAction SilentlyContinue;if($item -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'LinkedStationDataNotSupported'};$cursor=[IO.Path]::GetDirectoryName($cursor)}
}
function Find-BridgeAdapters {
 foreach($p in @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe' OR Name='pwsh.exe'")){
  $line=$p.CommandLine;if(!$line -or $line.Length -gt 65536){throw 'ProcessDiscoveryIncompleteRunLauncherAsAdministrator'}
  foreach($match in [regex]::Matches($line,'(?i)\s-([a-z]+)\s+([A-Za-z0-9+/=]+)(?:\s|$)')){
   if('encodedcommand'.StartsWith($match.Groups[1].Value.ToLowerInvariant())){
    try{$line+=' '+[Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($match.Groups[2].Value))}catch{throw 'UninspectableEncodedPowerShell'}
   }
  }
  if($line -match '(?i)(?:voice-adapter|capture-startup-adapter)\.ps1'){Write-Output $p}
 }
}
function Assert-Binary([string]$name){
 $manifest=Get-Content -LiteralPath (Join-Path $script:Bin 'artifact-hashes.json') -Raw|ConvertFrom-Json
 $expected=$manifest.$name
 if(!$expected -or (Get-FileHash -LiteralPath (Join-Path $script:Bin $name)).Hash -cne $expected){throw 'InstalledBinaryHashMismatch'}
}
function Initialize-PrivateData {
 Assert-DataPath $script:Root;Assert-DataPath (Join-Path $script:Root 'private-baseline')
 New-Item -ItemType Directory -Path $script:Root -Force|Out-Null
 $private=Join-Path $script:Root 'private-baseline';New-Item -ItemType Directory -Path $private -Force|Out-Null
 $acl=New-Object Security.AccessControl.DirectorySecurity
 $acl.SetAccessRuleProtection($true,$false)
 foreach($sid in @([Security.Principal.WindowsIdentity]::GetCurrent().User,(New-Object Security.Principal.SecurityIdentifier('S-1-5-18')),(New-Object Security.Principal.SecurityIdentifier('S-1-5-32-544')))){
  $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($sid,'FullControl','ContainerInherit,ObjectInherit','None','Allow')))
 };Set-Acl -LiteralPath $private -AclObject $acl
}
function Get-Station([switch]$RequireProfile,[object]$Candidate=$null){
 $path=Join-Path $script:Root 'station.json'
 Assert-DataPath $path
 if($null -eq $Candidate){if(!(Test-Path -LiteralPath $path)){throw 'StationSetupRequired'};$s=Get-Content -LiteralPath $path -Raw|ConvertFrom-Json}else{$s=$Candidate}
 if($s.SchemaVersion -ne 1 -or $s.Gateway -isnot [string] -or $s.Gateway -cnotmatch '^[A-Z0-9][A-Z0-9 /-]{0,9}$'){throw 'InvalidStationIdentity'}
 # Legacy own-room values may be retained, but current-room operation does not require one.
 if($s.OwnRoomId -and ($s.OwnRoomId -isnot [string] -or $s.OwnRoomId -cnotmatch '^[0-9]{5}$' -or $s.OwnRoomId -ceq '00000')){throw 'InvalidStationIdentity'}
 $ports=@($s.PhysicalPort,$s.NativePort,$s.AdapterPort)
 foreach($port in $ports){if($port -isnot [string] -or $port -cnotmatch '^COM[1-9][0-9]{0,3}$'){throw 'InvalidStationPort'}}
 if(@($ports|Select-Object -Unique).Count -ne 3){throw 'DistinctPortsRequired'}
 if($s.NativePath -isnot [string] -or ![IO.Path]::IsPathRooted($s.NativePath) -or [IO.Path]::GetFileName($s.NativePath) -ine 'Wires-X.exe'){throw 'SelectOfficialNativeExecutable'}
 if($RequireProfile){
  $p=Join-Path $script:Root 'private-baseline\radio-profile.json'
  Assert-DataPath $p
  if($s.RadioProfileSha256 -cnotmatch '^[A-F0-9]{64}$' -or !(Test-Path -LiteralPath $p) -or !(Get-Acl (Split-Path $p)).AreAccessRulesProtected -or (Get-FileHash -LiteralPath $p).Hash -cne $s.RadioProfileSha256){throw 'CaptureYourOwnRadioProfileFirst'}
 }
 return $s
}
function Save-Station($station){
 $null=Get-Station -Candidate $station
 New-Item -ItemType Directory -Path $script:Root -Force|Out-Null
 $path=Join-Path $script:Root 'station.json';$pending=$path+'.'+[Guid]::NewGuid().ToString('N')+'.pending'
 try{
  $station|ConvertTo-Json -Depth 6|Set-Content -LiteralPath $pending -Encoding UTF8
  if(Test-Path $path){[IO.File]::Replace($pending,$path,$path+'.backup-'+[DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffffffZ'))}else{[IO.File]::Move($pending,$path)}
 }finally{if(Test-Path $pending){Remove-Item -LiteralPath $pending}}
}
function Import-OwnProfile([string]$source){
 Assert-Binary 'BridgeProtocol.dll';[Reflection.Assembly]::LoadFrom((Join-Path $script:Bin 'BridgeProtocol.dll'))|Out-Null
 if((Get-Item -LiteralPath $source).Length -gt 1048576){throw 'MetadataTooLarge'}
 $f=Get-Content -LiteralPath $source -Raw|ConvertFrom-Json
 if($f.VoiceStored -ne $false -or $f.HriIdentityStored -ne $false -or !$f.Records -or $f.Records.Count -gt 500){throw 'ExpectedBoundedMetadataOnlyCapture'}
 $records=@();foreach($r in $f.Records){
  if($r.Direction -cnotin @('ClientToHri','HriToClient') -or $r.Body -isnot [string] -or $r.Body.Length -gt 1031 -or $r.Body -cnotmatch '^(D1[MVBCP][0-9A-F]{4}[ -~]*|B0[0-9 ]+)$'){throw 'UnexpectedMetadataRecord'}
  $records+=@{Direction=$r.Direction;Body=$r.Body}
 }
 $ids=@($records|Where-Object {$_.Direction -ceq 'HriToClient' -and $_.Body.StartsWith('D1V')})
 if(!$ids.Count){throw 'MissingRadioIdentification'};$null=[CumbriaCQ.Offline.RadioIdReply]::new($ids[0].Body)
 $queries=@($records|Where-Object {$_.Direction -ceq 'ClientToHri' -and $_.Body.StartsWith('D1M')}|ForEach-Object {$_.Body}|Select-Object -Unique)
 $replies=@($records|Where-Object {$_.Direction -ceq 'HriToClient' -and $_.Body.StartsWith('D1M')}|ForEach-Object {$_.Body}|Select-Object -Unique)
 if($queries.Count -ne 1 -or $replies.Count -ne 1){throw 'ConsistentConfigurationPairRequired'}
 $null=[CumbriaCQ.Offline.ConfigurationReply]::new($queries[0],$replies[0])
 foreach($kind in @('D1C','D1P','D1B')){
  $b=@($records|Where-Object {$_.Direction -ceq 'HriToClient' -and $_.Body.StartsWith($kind)}|ForEach-Object {$_.Body}|Select-Object -Unique)
  if($b.Count -ne 1){throw 'IncompleteRadioProfile'}
 }
 $status=@($records|Where-Object {$_.Direction -ceq 'HriToClient' -and $_.Body.StartsWith('D1C')})[0].Body
 $idle=@($records|Where-Object {$_.Direction -ceq 'HriToClient' -and $_.Body -cmatch '^B0[0-9 ]+$'})
 if(!$idle.Count){throw 'MissingIdleMetadata'}
 $s=Get-Station
 $null=[CumbriaCQ.Offline.VoiceEngine]::new($s.Gateway,0,$status,$idle[-1].Body,$false,$true)
 Initialize-PrivateData;$target=Join-Path $script:Root 'private-baseline\radio-profile.json'
 $pending=$target+'.pending';@{Records=$records;VoiceStored=$false;HriIdentityStored=$false}|ConvertTo-Json -Depth 6|Set-Content $pending -Encoding UTF8
 if(Test-Path $target){[IO.File]::Replace($pending,$target,$target+'.backup-'+[DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffffffZ'))}else{[IO.File]::Move($pending,$target)}
 $s.RadioProfileSha256=(Get-FileHash $target).Hash;Save-Station $s
}
function New-DiscoveryBackup($station){
 $path=Join-Path $script:Root 'discovery-name-backup.json'
 Assert-DataPath $path
 if(Test-Path $path){return}
 $entries=@();foreach($port in @($station.PhysicalPort,$station.NativePort)){
  $devices=@(Get-PnpDevice -Class Ports -PresentOnly|Where-Object {$_.FriendlyName -cmatch ('\('+[regex]::Escape($port)+'\)$')})
  if($devices.Count -ne 1 -or $devices[0].Status -ne 'OK'){throw 'SelectHealthyUnambiguousPorts'}
  $virtual=$devices[0].InstanceId -like 'COM0COM\*'
  if(($port -ceq $station.NativePort) -ne $virtual){throw 'NativePortMustBeSignedCom0comEndpoint'}
  if(!$virtual -and $devices[0].FriendlyName -cnotmatch '^HRI-200 Communication device A \(COM[0-9]+\)$'){throw 'PhysicalPortMustBeGenuineHri200'}
  $entries+=@{Path=('HKLM:\SYSTEM\CurrentControlSet\Enum\'+$devices[0].InstanceId);FriendlyName=$devices[0].FriendlyName}
 }
 $entries|ConvertTo-Json|Set-Content -LiteralPath $path -Encoding UTF8
}
