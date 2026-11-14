# Copyright (c) 2026 M5LEE. Explicit, local-only migration; never executes source scripts.
# SPDX-License-Identifier: GPL-3.0-or-later
function Read-ExistingFile([string]$Source,[string]$Relative,[int]$Limit=1048576){
 $base=[IO.Path]::GetFullPath($Source).TrimEnd('\');$path=[IO.Path]::GetFullPath((Join-Path $base $Relative))
 if(!$path.StartsWith($base+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'ImportPathOutsideSelectedFolder'}
 $cursor=$path
 while($cursor){$item=Get-Item -LiteralPath $cursor -Force -ErrorAction SilentlyContinue;if($item -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'LinkedImportDataNotSupported'};$cursor=[IO.Path]::GetDirectoryName($cursor)}
 if((Get-Item -LiteralPath $path).Length -gt $Limit){throw 'ImportFileTooLarge'}
 $stream=[IO.File]::Open($path,[IO.FileMode]::Open,[IO.FileAccess]::Read,([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete));$reader=[IO.StreamReader]::new($stream)
 try{return $reader.ReadToEnd()}finally{$reader.Dispose()}
}
function Import-ExistingStation([string]$Source,[hashtable]$Ops=$null,[string]$YsfCallsign=''){
 Assert-DataPath $script:Root
 if($YsfCallsign -and $YsfCallsign -cnotmatch '^[A-Z0-9][A-Z0-9 /-]{0,9}$'){throw 'InvalidYsfBridgeCallsign'}
 $sourceRoot=[IO.Path]::GetFullPath($Source).TrimEnd('\')
 if($sourceRoot -ieq [IO.Path]::GetFullPath($script:Root).TrimEnd('\')){throw 'SelectTheOldWorkingBridgeFolder'}
 $stationPath=Join-Path $script:Root 'station.json';$profilePath=Join-Path $script:Root 'private-baseline\radio-profile.json'
 if((Test-Path $stationPath) -or (Test-Path $profilePath)){throw 'StationAlreadyPresentNoOverwrite'}
 if(!$Ops){$Ops=@{Native={Find-InstalledWiresX ''};Pair={param($a,$b)$matches=@(Get-InstalledPairs|Where-Object {$_.NativePort -ceq $a -and $_.AdapterPort -ceq $b});return ($matches.Count -eq 1 -and (Test-PairHealthy $matches[0]))}}}
 $code=Read-ExistingFile $sourceRoot 'voice-adapter.ps1' 65536
 $real=[regex]::Match($code,'(?m)^\$real=New-Object IO\.Ports\.SerialPort ''(COM[1-9][0-9]{0,3})'',')
 $virt=[regex]::Match($code,'(?m)^\$virt=New-Object IO\.Ports\.SerialPort ''(COM[1-9][0-9]{0,3})'',')
 $fixture=[regex]::Match($code,'(?m)^\$fixture=Join-Path \$private ''([^'']+\.json)''\s*$')
 if(!$real.Success -or !$virt.Success -or !$fixture.Success -or [IO.Path]::GetFileName($fixture.Groups[1].Value) -cne $fixture.Groups[1].Value){throw 'UnrecognisedWorkingBridgeLayout'}
 $physical=$real.Groups[1].Value;$adapter=$virt.Groups[1].Value
 $aliases=Read-ExistingFile $sourceRoot 'discovery-name-backup.json' 16384|ConvertFrom-Json
 if($aliases.Count -ne 2){throw 'ExistingPortBackupAmbiguous'}
 $native=@($aliases|Where-Object {$_.Path -like 'HKLM:\SYSTEM\CurrentControlSet\Enum\COM0COM\PORT\*' -and $_.FriendlyName -cmatch '\((COM[1-9][0-9]{0,3})\)$'})
 if($native.Count -ne 1){throw 'ExistingVirtualPortNotIdentified'}
 $nativePort=[regex]::Match($native[0].FriendlyName,'\((COM[1-9][0-9]{0,3})\)$').Groups[1].Value
 if(!(& $Ops.Pair $nativePort $adapter)){throw 'ExistingVirtualPairNotVerified'}
 $nativePath=& $Ops.Native
 $latest=Get-ChildItem -LiteralPath $sourceRoot -Filter 'progress-bridge*.json' -File|Sort-Object LastWriteTimeUtc -Descending|Select-Object -First 1
 if(!$latest){throw 'ExistingStationProgressRequired'}
 $progress=Read-ExistingFile $sourceRoot $latest.Name 65536|ConvertFrom-Json
 if($progress.Tag -cnotmatch '^bridge[A-Za-z0-9]+$' -or $latest.Name -cne ('progress-'+$progress.Tag+'.json')){throw 'ExistingProgressBindingInvalid'}
 $capture=Read-ExistingFile $sourceRoot ('private-baseline\'+$fixture.Groups[1].Value)|ConvertFrom-Json
 if($capture.VoiceStored -ne $false -or $capture.HriIdentityStored -ne $false -or !$capture.Records -or $capture.Records.Count -gt 500){throw 'MetadataOnlyProfileRequired'}
 $records=@();foreach($r in $capture.Records){
  if($r.Direction -cnotin @('ClientToHri','HriToClient') -or $r.Body -isnot [string]){throw 'InvalidExistingMetadata'}
  if($r.Direction -ceq 'ClientToHri' -and $r.Body -ceq 'P010000'){continue}
  if($r.Body.Length -gt 1031 -or $r.Body -cnotmatch '^(D1[MVBCP][0-9A-F]{4}[ -~]*|B0[0-9 ]+)$'){throw 'UnexpectedExistingMetadata'}
  $records+=@{Direction=$r.Direction;Body=$r.Body}
 }
 $bridgeCallsign=if($YsfCallsign){$YsfCallsign}else{$progress.Gateway}
 $station=[pscustomobject]@{SchemaVersion=1;Gateway=$bridgeCallsign;OwnRoomId='';PhysicalPort=$physical;NativePort=$nativePort;AdapterPort=$adapter;NativePath=$nativePath;RadioProfileSha256=''}
 $null=Get-Station -Candidate $station
 Assert-Binary 'BridgeConfigCore.dll';[Reflection.Assembly]::LoadFrom((Join-Path $script:Bin 'BridgeConfigCore.dll'))|Out-Null
 $configSource=Join-Path $sourceRoot 'bridge-config.json';if(Test-Path $configSource){$null=Read-ExistingFile $sourceRoot 'bridge-config.json' 65536}
 $settings=[CumbriaCQ.Configuration.SettingsStore]::Open($configSource).Settings
 $configPath=Join-Path $script:Root 'bridge-config.json';Assert-DataPath $configPath
 Initialize-PrivateData;$pending=Join-Path $script:Root 'private-baseline\existing-import.pending.json';$configCreated=$false
 try{
  Save-Station $station
  @{VoiceStored=$false;HriIdentityStored=$false;Records=$records}|ConvertTo-Json -Depth 6|Set-Content -LiteralPath $pending -Encoding UTF8
  Import-OwnProfile $pending
  if(!(Test-Path $configPath)){$null=[CumbriaCQ.Configuration.SettingsStore]::Save($configPath,$settings,'MISSING');$configCreated=$true}
  return (Get-Station -RequireProfile)
 }catch{
  Remove-Item -LiteralPath $stationPath,$profilePath -Force -ErrorAction SilentlyContinue
  if($configCreated){Remove-Item -LiteralPath $configPath -Force -ErrorAction SilentlyContinue}
  throw
 }finally{Remove-Item -LiteralPath $pending -Force -ErrorAction SilentlyContinue}
}
