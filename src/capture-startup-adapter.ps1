param([ValidateRange(60,180)][int]$Seconds=120,[string]$Tag='capture')
$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
if($Tag -cnotmatch '^[A-Za-z0-9]+$'){throw 'InvalidCaptureTag'}
. (Join-Path $PSScriptRoot 'PublicRuntime.ps1')
$root=$script:Root;$station=Get-Station;Initialize-PrivateData
$private=Join-Path $root 'private-baseline'
if(!(Get-Acl $private).AreAccessRulesProtected){throw 'Private baseline ACL not protected'}
function Test-SafeBody([string]$body){
 if($body -cin @('M00','M10','R6423','P010000','D1V0000','D1C0000','D1B00010')){return $true}
 # Upstream block(): decimal frequencies and signed decimal offsets, not hex-only.
 return ($body -cmatch '^D1M0045[0-9A-F]{4}([ 0-9]{3}\.[0-9]{5}[+-][0-9]{3}\.[0-9]{5}[0-9A-F]{13}){2}F$')
}
$good='D1M0045'+'7000'+(('433.00000+000.00000'+('0'*13))*2)+'F'
if(!(Test-SafeBody $good) -or !(Test-SafeBody 'M10') -or !(Test-SafeBody 'P010000')){throw 'Whitelist positive self-test failed'}
foreach($bad in @('P100100','P110000','D1E00892','D1R00892','D1M0000','R0000',($good+'F'),('D1M0045'+('X'*69)))){if(Test-SafeBody $bad){throw 'Whitelist negative self-test failed'}}
$real=New-Object IO.Ports.SerialPort $station.PhysicalPort,38400,([IO.Ports.Parity]::None),8,([IO.Ports.StopBits]::One)
$virt=New-Object IO.Ports.SerialPort $station.AdapterPort,38400,([IO.Ports.Parity]::None),8,([IO.Ports.StopBits]::One)
foreach($p in @($real,$virt)){$p.DtrEnable=$false;$p.RtsEnable=$false;$p.Handshake='None';$p.WriteTimeout=500}
$hostBuffer='';$realBuffer='';$seen=@{};$hardware=@{};$blocked=@{};$records=New-Object Collections.Generic.List[object];$firstConfig=$null;$failure=$null
function Count-Key($table,$key){if(!$table.ContainsKey($key)){$table[$key]=0};$table[$key]++}
function Save-Metadata($direction,$body){if($records.Count -lt 500){$records.Add([pscustomobject]@{Ms=$clock.ElapsedMilliseconds;Direction=$direction;Body=$body})}}
try{
 if(Get-Process Wires-X -ErrorAction SilentlyContinue){throw 'Start adapter before WIRES-X'}
 $real.Open();$virt.Open();Start-Sleep -Seconds 7
 'ADAPTER_READY;VOICE=False;PHYSICAL_TRANSMIT=False;SAVED_CONFIG_ONLY=True'
 $clock=[Diagnostics.Stopwatch]::StartNew()
 while($clock.Elapsed.TotalSeconds -lt $Seconds){
  if($virt.BytesToRead -gt 0){
   $hostBuffer+=$virt.ReadExisting()
   foreach($m in [regex]::Matches($hostBuffer,"\x01([^\x01\x04]*)\x04")){
    $b=$m.Groups[1].Value;$key=if($b -match '^[A-Z][0-9]{2,6}$'){$b}else{$b.Substring(0,[Math]::Min(3,$b.Length))+' length='+$b.Length};Count-Key $seen $key
    $allowed=Test-SafeBody $b
    if($allowed -and $b.StartsWith('D1M')){if($null -eq $firstConfig){$firstConfig=$b}elseif($b -cne $firstConfig){$allowed=$false;Count-Key $blocked 'changed-configuration'}}
    if($allowed){if($b -notin @('M00','M10','R6423')){Save-Metadata 'ClientToHri' $b};$real.Write(([char]1)+$b+([char]4))}
    else{Count-Key $blocked $key}
   }
   $last=$hostBuffer.LastIndexOf([char]4);if($last -ge 0){$hostBuffer=$hostBuffer.Substring($last+1)};if($hostBuffer.Length -gt 8192){$hostBuffer=''}
  }
  if($real.BytesToRead -gt 0){
   $realBuffer+=$real.ReadExisting()
   foreach($m in [regex]::Matches($realBuffer,"\x01([^\x01\x04]*)\x04")){
    $b=$m.Groups[1].Value;$kind=$null;$metadata=$false
    if($b -in @('M00','M10')){$kind='handshake'}
    elseif($b -match '^R[0-9A-Fa-f]+$'){$kind='genuine-HRI-identity'}
    elseif($b -match '^B0[0-9 ]+$'){$kind='idle-poll';$metadata=$true}
    elseif($b -cmatch '^D1[MVBCP][0-9A-Fa-f]{4}[ -~]*$'){
     $n=[Convert]::ToInt32($b.Substring(3,4),16)
     if($n -le 1024 -and $b.Length -eq $n+7){$kind=$b.Substring(0,3);$metadata=$true}
    }
    if($kind){if($metadata){Save-Metadata 'HriToClient' $b};$virt.Write(([char]1)+$b+([char]4));Count-Key $hardware $kind}
   }
   $last=$realBuffer.LastIndexOf([char]4);if($last -ge 0){$realBuffer=$realBuffer.Substring($last+1)};if($realBuffer.Length -gt 8192){$realBuffer=''}
  }
  Start-Sleep -Milliseconds 25
 }
}catch{$failure=$_.Exception.Message;throw}
finally{
 foreach($p in @($real,$virt)){if($p.IsOpen){$p.Close()};$p.Dispose()}
 $path=Join-Path $private ('startup-'+$Tag+'.json')
 [pscustomobject]@{Tag=$Tag;Records=$records.ToArray();VoiceStored=$false;HriIdentityStored=$false}|ConvertTo-Json -Depth 5|Set-Content $path
 $result=[pscustomobject]@{Tag=$Tag;HostCommands=$seen;GenuineHardwareReplies=$hardware;BlockedCommands=$blocked;MetadataRecords=$records.Count;PrivateFile=$path;Error=$failure;PortsReleased=$true;VoiceForwarded=$false;PhysicalPttOn=$false}
 $result|ConvertTo-Json -Depth 5|Set-Content (Join-Path $root ('adapter-'+$Tag+'-result.json'))
 $result|ConvertTo-Json -Depth 5 -Compress
}
