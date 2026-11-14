# Copyright (c) 2026 M5LEE. Bundled com0com retains its upstream GPL licence.
# SPDX-License-Identifier: GPL-3.0-or-later
# Dot-sourcing defines functions only. Provisioning needs an explicit UI action.
$script:ConnectionBin=$PSScriptRoot
function ConvertFrom-PairList([string]$text){
 $groups=@{}
 foreach($line in ($text -split '\r?\n')){
  if($line -notmatch '^\s*CNC([AB])([0-9]+)\s+(.+)$'){continue}
  $side=$Matches[1];$id=[int]$Matches[2];$params=$Matches[3];$port=$null
  if($params -match '(?:^|,)RealPortName=(COM[1-9][0-9]{0,3})(?:,|$)'){$port=$Matches[1]}
  elseif($params -match '(?:^|,)PortName=(COM[1-9][0-9]{0,3})(?:,|$)'){$port=$Matches[1]}
  if(!$port){continue};if(!$groups.ContainsKey($id)){$groups[$id]=@{}}
  if($groups[$id].ContainsKey($side)){throw 'DuplicateVirtualEndpoint'};$groups[$id][$side]=$port
 }
 foreach($id in @($groups.Keys|Sort-Object)){
  $g=$groups[$id];if($g.A -and $g.B){if($g.A -ceq $g.B){throw 'InvalidVirtualPair'};[pscustomobject]@{Id=$id;NativePort=$g.A;AdapterPort=$g.B}}
 }
}
function Assert-FirstRunSafe {
 $principal=New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
 if(!$principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw 'Open Station setup from the Start menu and approve the administrator prompt.'}
 if(@(Find-BridgeAdapters).Count -or (Test-Path (Join-Path $script:Root 'launcher-state\owner.json'))){throw 'A bridge is running or needs cleanup. No device changes were made. Stop it normally before automatic setup.'}
}
function Find-InstalledWiresX([string]$selected){
 $paths=@($selected,(Join-Path ${env:ProgramFiles(x86)} 'YAESUMUSEN\WIRES-X\Wires-X.exe'),(Join-Path $env:ProgramFiles 'YAESUMUSEN\WIRES-X\Wires-X.exe'))
 foreach($key in @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\Wires-X.exe','HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\App Paths\Wires-X.exe')){
  $item=Get-ItemProperty $key -ErrorAction SilentlyContinue;if($item){$paths+=,$item.'(default)'}
 }
 foreach($path in @($paths|Where-Object {$_}|Select-Object -Unique)){
  if((Test-Path -LiteralPath $path -PathType Leaf) -and [IO.Path]::GetFileName($path) -ieq 'Wires-X.exe' -and (Get-FileHash -LiteralPath $path).Hash -ceq $script:SupportedNativeHash){return $path}
 }
 throw 'The supported WIRES-X installation was not found. Install official WIRES-X 2.0.1.0, or select its executable under Advanced.'
}
function Find-HriPort([string]$selected){
 # Friendly names may be localized or temporarily aliased. Identify communication A by USB hardware ID.
 $ports=@(Get-CimInstance Win32_PnPEntity|Where-Object {$_.DeviceID -like 'USB\*' -and $_.ConfigManagerErrorCode -eq 0 -and @($_.HardwareID|Where-Object {$_ -match '^USB\\VID_26AA&PID_0002(?:&|$)'}).Count -gt 0}|ForEach-Object {if($_.Name -match '\((COM[1-9][0-9]{0,3})\)$'){$Matches[1]}}|Select-Object -Unique)
 if($selected -and $selected -cin $ports){return $selected}
 if($selected){throw 'The selected HRI port is not a healthy genuine HRI-200 communication-A interface. Check the USB cable or clear the selection for automatic discovery.'}
 if($ports.Count -eq 1){return $ports[0]}
 if(!$ports.Count){throw 'Connect the genuine HRI-200 USB cable and install its official Yaesu driver, then try again.'}
 throw 'More than one HRI-200 was found. Select your HRI port, then retry automatic setup.'
}
function Assert-DriverPayload([string]$name,[switch]$Signature){
 $dir=Join-Path $script:ConnectionBin 'vendor\com0com';$manifest=Get-Content (Join-Path $dir 'hashes.json') -Raw|ConvertFrom-Json
 $path=Join-Path $dir $name
 if(!$manifest.$name -or (Get-FileHash -LiteralPath $path).Hash -cne $manifest.$name){throw 'Bundled driver integrity check failed. Reinstall the bridge from the verified release.'}
 if($Signature -and (Get-AuthenticodeSignature -LiteralPath $path).Status -ne 'Valid'){throw 'Windows could not validate the bundled driver signature. No security settings were changed.'}
 return $path
}
function Invoke-BoundedSetupProcess([string]$exe,[string]$arguments,[string]$directory,[hashtable]$environment){
 $info=New-Object Diagnostics.ProcessStartInfo($exe,$arguments);$info.WorkingDirectory=$directory;$info.UseShellExecute=$false;$info.CreateNoWindow=$true;$info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
 foreach($key in $environment.Keys){$info.EnvironmentVariables[$key]=$environment[$key]}
 $p=New-Object Diagnostics.Process;$p.StartInfo=$info
 try{
  if(!$p.Start()){throw 'Windows did not start the setup tool.'}
  $output=$p.StandardOutput.ReadToEndAsync();$errorOutput=$p.StandardError.ReadToEndAsync()
  if(!$p.WaitForExit(120000)){throw 'Driver setup did not finish within two minutes. Do not retry until its Windows installer has finished.'}
  return [pscustomobject]@{ExitCode=$p.ExitCode;Output=$output.Result;ErrorOutput=$errorOutput.Result}
 }finally{$p.Dispose()}
}
function Invoke-DriverTool([string]$name,[string]$arguments,[switch]$Installer){
 Assert-DataPath $script:Root
 foreach($critical in @('setup.dll','com0com.sys','com0com.cat','com0com.inf','comport.inf','cncport.inf')){$null=Assert-DriverPayload $critical}
 $exe=Assert-DriverPayload $name -Signature
 $directory=Split-Path $exe
 New-Item -ItemType Directory -Force $script:Root|Out-Null
 $environment=@{};if($Installer){foreach($key in @('CNC_INSTALL_START_MENU_SHORTCUTS','CNC_INSTALL_CNCA0_CNCB0_PORTS','CNC_INSTALL_COMX_COMX_PORTS')){$environment[$key]='NO'}}
 $result=Invoke-BoundedSetupProcess $exe $arguments $directory $environment
 $log=Join-Path $script:Root ('setup-'+[Guid]::NewGuid().ToString('N')+'.out');[IO.File]::WriteAllText($log,$result.Output);[IO.File]::WriteAllText(($log+'.err'),$result.ErrorOutput)
 if($result.ExitCode -notin @(0,3010)){throw ('Windows could not set up the virtual-port driver (exit '+$result.ExitCode+'). No security settings were changed; check Windows driver compatibility.')}
 if($result.ExitCode -eq 3010){throw 'Windows requires a restart to finish installing the virtual-port driver. Restart when convenient and run automatic setup again.'}
 return $result.Output
}
function Get-InstalledPairs {ConvertFrom-PairList ([string](Invoke-DriverTool 'setupc.exe' 'list'))}
function Test-PairHealthy($pair){
 $inventory=@([IO.Ports.SerialPort]::GetPortNames());if($pair.NativePort -cnotin $inventory -or $pair.AdapterPort -cnotin $inventory){return $false}
 $devices=@(Get-CimInstance Win32_PnPEntity|Where-Object {$_.DeviceID -like 'COM0COM\*' -and $_.ConfigManagerErrorCode -eq 0})
 foreach($port in @($pair.NativePort,$pair.AdapterPort)){if(!@($devices|Where-Object {$_.Name -match ('\('+[regex]::Escape($port)+'\)$')}).Count){return $false}}
 return $true
}
function Initialize-StationConnections([string]$Gateway,[string]$OwnRoomId,[string]$PhysicalPort='',[string]$NativePath='',[hashtable]$Ops=$null){
 Assert-DataPath $script:Root
 if($Gateway -cnotmatch '^[A-Z0-9][A-Z0-9 /-]{0,9}$' -or ($OwnRoomId -and ($OwnRoomId -cnotmatch '^[0-9]{5}$' -or $OwnRoomId -ceq '00000'))){throw 'Enter the YSF bridge callsign (maximum 10 characters). No WIRES-X gateway ID, node number or fixed room is required.'}
 if(!$Ops){$Ops=@{Guard={Assert-FirstRunSafe};Native={param($path)Find-InstalledWiresX $path};Physical={param($port)Find-HriPort $port};Installed={return [bool](Get-CimInstance Win32_SystemDriver -Filter "Name='com0com'")};Install={foreach($name in @('com0com.sys','com0com.cat')){$null=Assert-DriverPayload $name -Signature};$null=Invoke-DriverTool 'Setup_com0com_v3.0.0.0_W7_x64_signed.exe' '/S' -Installer};Pairs={Get-InstalledPairs};Create={$null=Invoke-DriverTool 'setupc.exe' 'install PortName=COM#,EmuOverrun=yes PortName=COM#,EmuOverrun=yes'};Healthy={param($pair)Test-PairHealthy $pair}}}
 & $Ops.Guard
 $path=& $Ops.Native $NativePath;$physical=& $Ops.Physical $PhysicalPort
 $lock=New-Object Threading.Mutex($false,'Global\M5LEE.WiresX2YSF.Provisioning');$held=$false
 try{
  $held=$lock.WaitOne(0);if(!$held){throw 'Another automatic setup is already running.'}
  $old=$null;try{$old=Get-Station}catch{}
  if(!(& $Ops.Installed)){& $Ops.Install}
  $before=@(& $Ops.Pairs);$pair=$null
  if($old){$matching=@($before|Where-Object {$_.NativePort -ceq $old.NativePort -and $_.AdapterPort -ceq $old.AdapterPort});if($matching.Count -eq 1){$pair=$matching[0]}}
  $journal=Join-Path $script:Root 'connection-setup.json'
  if(!$pair -and (Test-Path $journal)){
   $prior=Get-Content $journal -Raw|ConvertFrom-Json
   if($prior.State -in @('Created','Complete')){$matching=@($before|Where-Object {$_.Id -eq $prior.PairId -and $_.NativePort -ceq $prior.NativePort -and $_.AdapterPort -ceq $prior.AdapterPort});if($matching.Count -eq 1){$pair=$matching[0]}}
   if(!$pair -and $prior.State -ne 'Complete'){throw 'Previous virtual-port setup needs inspection; no additional pair was created.'}
  }
  if(!$pair){
   # Record the pre-change inventory before creating anything; do not adopt somebody else's pair.
   New-Item -ItemType Directory -Force $script:Root|Out-Null

   @{State='Creating';BeforePairIds=@($before|ForEach-Object {$_.Id});Utc=[DateTime]::UtcNow.ToString('o')}|ConvertTo-Json -Depth 5|Set-Content $journal -Encoding UTF8
   & $Ops.Create
   $after=@(& $Ops.Pairs);$created=@($after|Where-Object {$_.Id -notin @($before|ForEach-Object {$_.Id})})
   if($created.Count -ne 1){throw 'Windows did not create exactly one identifiable virtual pair. Setup stopped without changing your station settings.'};$pair=$created[0]
   @{State='Created';PairId=$pair.Id;NativePort=$pair.NativePort;AdapterPort=$pair.AdapterPort}|ConvertTo-Json|Set-Content $journal -Encoding UTF8
  }
  $healthy=$false
  for($attempt=0;$attempt -lt 30;$attempt++){if(& $Ops.Healthy $pair){$healthy=$true;break};if($Ops.ContainsKey('Wait')){& $Ops.Wait}elseif(!$Ops.ContainsKey('Wait') -and $null -eq $PSBoundParameters['Ops']){Start-Sleep -Milliseconds 500}}
  if(!$healthy){throw 'Windows has not loaded both virtual ports successfully. The driver may be blocked by Windows security or require a restart. No security settings were changed and your station was not overwritten.'}
  $station=[pscustomobject]@{SchemaVersion=1;Gateway=$Gateway;OwnRoomId=$OwnRoomId;PhysicalPort=$physical;NativePort=$pair.NativePort;AdapterPort=$pair.AdapterPort;NativePath=$path;RadioProfileSha256=''}
  if($old){$same=$true;foreach($key in @('PhysicalPort','NativePort','AdapterPort','NativePath')){if($station.$key -cne $old.$key){$same=$false}};if($same){$station.RadioProfileSha256=$old.RadioProfileSha256}}
  Save-Station $station
  @{State='Complete';PairId=$pair.Id;NativePort=$pair.NativePort;AdapterPort=$pair.AdapterPort}|ConvertTo-Json|Set-Content (Join-Path $script:Root 'connection-setup.json') -Encoding UTF8
  return $station
 }finally{if($held){$lock.ReleaseMutex()};$lock.Dispose()}
}
