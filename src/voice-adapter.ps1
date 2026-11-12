param([ValidateRange(60,18000)][int]$Seconds=600,[string]$Tag='voicepilot',[switch]$ForwardVoice,[ValidateSet('BridgeProtocol.dll')][string]$AssemblyName='BridgeProtocol.dll')
# Experimental, bounded own-room bridge. Physical hardware sees M00/M10/R6423 only.
$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
if($Tag -cnotmatch '^[A-Za-z0-9]+$'){throw 'Invalid trial tag'}
. (Join-Path $PSScriptRoot 'PublicRuntime.ps1')
$root=$script:Root;$station=Get-Station -RequireProfile
. (Join-Path $script:Bin 'Get-BridgeSettings.ps1')
$settings=Get-BridgeSettings (Join-Path $root 'bridge-config.json') (Join-Path $script:Bin 'BridgeConfigCore.dll')
$private=Join-Path $root 'private-baseline'
if(!(Get-Acl $private).AreAccessRulesProtected){throw 'Protected metadata ACL missing'}
$fixture=Join-Path $private 'radio-profile.json'
if((Get-FileHash $fixture).Hash -ne $station.RadioProfileSha256){throw 'Baseline hash changed'}
Assert-Binary 'BridgeProtocol.dll';[Reflection.Assembly]::LoadFrom((Join-Path $script:Bin $AssemblyName))|Out-Null
$f=Get-Content $fixture -Raw|ConvertFrom-Json
$ids=@($f.Records|Where-Object {$_.Direction -eq 'HriToClient' -and $_.Body.StartsWith('D1V')}|ForEach-Object {$_.Body})
$idReply=[CumbriaCQ.Offline.RadioIdReply]::new($ids[0])
$idText=[Text.Encoding]::ASCII.GetString($idReply.ForQuery('D1V0000'))
$sent=@($f.Records|Where-Object {$_.Direction -eq 'ClientToHri' -and $_.Body.StartsWith('D1M')})[0].Body
$returned=@($f.Records|Where-Object {$_.Direction -eq 'HriToClient' -and $_.Body.StartsWith('D1M')})[0].Body
$configReply=[CumbriaCQ.Offline.ConfigurationReply]::new($sent,$returned)
$idles=@($f.Records|Where-Object {$_.Direction -eq 'HriToClient' -and $_.Body -match '^B0[0-9 ]+$'}|ForEach-Object {$_.Body})
$replies=@{}
foreach($kind in 'D1C','D1P','D1B'){$bodies=@($f.Records|Where-Object {$_.Direction -eq 'HriToClient' -and $_.Body.StartsWith($kind)}|ForEach-Object {$_.Body}|Select-Object -Unique);if($bodies.Count -ne 1){throw 'Missing consistent metadata fixture'};$replies[$kind]=$bodies[0]}
$engine=[CumbriaCQ.Offline.VoiceEngine]::new($station.Gateway,$settings.DgId,$replies['D1C'],$idles[-1],$settings.AllowZeroDg,$true)
if($AssemblyName -in @('BridgeProtocol.dll')){
 # Explicit experimental own-room addressing, not a measured RF-header claim.
 # Only the existing owned emulated-set ID is reused; no remote ID is invented.
 $engine=[CumbriaCQ.Offline.VoiceEngine]::new($station.Gateway,$settings.DgId,$replies['D1C'],$idles[-1],$settings.AllowZeroDg,$station.OwnRoomId,$replies['D1C'].Substring(12,5))
}
$real=New-Object IO.Ports.SerialPort $station.PhysicalPort,38400,([IO.Ports.Parity]::None),8,([IO.Ports.StopBits]::One)
$virt=New-Object IO.Ports.SerialPort $station.AdapterPort,38400,([IO.Ports.Parity]::None),8,([IO.Ports.StopBits]::One)
foreach($p in @($real,$virt)){$p.DtrEnable=$false;$p.RtsEnable=$false;$p.Handshake='None';$p.WriteTimeout=500}
$hostParser=[CumbriaCQ.Offline.FrameParser]::new(1024);$realParser=[CumbriaCQ.Offline.FrameParser]::new(1024)
$addresses=@([Net.Dns]::GetHostAddresses($settings.YsfHost))
$address=@($addresses|Where-Object {$_.AddressFamily -eq [Net.Sockets.AddressFamily]::InterNetwork})[0]
if(!$address){$address=@($addresses|Where-Object {$_.AddressFamily -eq [Net.Sockets.AddressFamily]::InterNetworkV6})[0]}
if(!$address){throw 'Reflector host has no supported IP address'}
$socket=[Net.Sockets.UdpClient]::new($address.AddressFamily);$socket.Client.ReceiveTimeout=500;$socket.Connect($address,$settings.YsfPort)
$receiveAny=if($address.AddressFamily -eq [Net.Sockets.AddressFamily]::InterNetworkV6){[Net.IPAddress]::IPv6Any}else{[Net.IPAddress]::Any}
$poll=[Text.Encoding]::ASCII.GetBytes('YSFP'+$station.Gateway.PadRight(10));$unlink=[Text.Encoding]::ASCII.GetBytes('YSFU'+$station.Gateway.PadRight(10))
$configured=$false;$roomVerified=$false;$linkHealthy=$false;$wasActive=$false;$nodeSaved=$false;$proofReason='not-yet-read'
$seen=@{};$hardware=@{};$wireOut=@{};$networkOut=@{};$dropped=@{};$counts=@{Polls=0;PollReplies=0;ValidOwnRoom=0;OtherOrInvalidRoom=0;NetworkData=0;GateDrops=0;PhysicalControlsBlocked=0;Configurations=0}
$failure=$null;$nextPoll=0;$lastAck=-1;$lastStopCheck=0;$lastProofCheck=-1000;$clock=$null;$cpuStart=0
function Count-Key($table,$key){if(!$table.ContainsKey($key)){$table[$key]=0};$table[$key]++}
function Reply-Frame([string]$body){$virt.Write(([char]1)+$body+([char]4));$key=$body.Substring(0,[Math]::Min(3,$body.Length));Count-Key $wireOut $key}
function Send-Batch($batch,[bool]$endingOnly=$false){
 foreach($frame in $batch.Serial){if($frame.StartsWith('P')){throw 'Physical control in software response output'};Reply-Frame $frame}
 foreach($packet in $batch.Network){
  if($ForwardVoice -and (($configured -and $roomVerified -and $linkHealthy) -or ($endingOnly -and (($packet[34] -band 1) -eq 1)))){
   $null=$socket.Send($packet,$packet.Length);Count-Key $networkOut 'YSFD';if(($packet[34] -band 1) -ne 0){Count-Key $networkOut 'EOT'}
  }else{Count-Key $dropped 'network-output-gated'}
 }
}
try{
 if(Get-Process Wires-X -ErrorAction SilentlyContinue){throw 'Start adapter before WIRES-X'}
 $real.Open();$virt.Open();Start-Sleep -Seconds 7
 "ADAPTER_READY;EXPERIMENTAL_VOICE=True;PHYSICAL_TRANSMIT=False;OWN_ROOM_GATE=$($station.OwnRoomId)"
 $clock=[Diagnostics.Stopwatch]::StartNew();$cpuStart=[Diagnostics.Process]::GetCurrentProcess().TotalProcessorTime.TotalSeconds
 while($clock.Elapsed.TotalSeconds -lt $Seconds){
  $now=$clock.ElapsedMilliseconds
  if($now-$lastProofCheck -ge 1000){
   $lastProofCheck=$now;$roomVerified=$false;$proofReason='missing-or-invalid'
   try{
    $proof=Get-Content (Join-Path $root ('room-proof-'+$Tag+'.json')) -Raw -ErrorAction Stop|ConvertFrom-Json
    $age=([DateTime]::UtcNow-[DateTime]::Parse($proof.Utc).ToUniversalTime()).TotalSeconds
    $app=Get-Process Wires-X -ErrorAction Stop
    $roomVerified=($proof.Tag -ceq $Tag -and $proof.Method -ceq 'NativeMainLog' -and $proof.ControlId -eq 1014 -and $proof.AppPid -eq $app.Id -and $proof.Connected -eq $true -and $proof.RoomId -ceq $station.OwnRoomId -and $age -ge 0 -and $age -le 8 -and !$proof.Error)
    $proofReason=if($roomVerified){'verified'}elseif($age -gt 8 -or $age -lt 0){'stale'}elseif($proof.AppPid -ne $app.Id){'different-process'}elseif($proof.Error){'observer-error'}else{'not-connected-or-untrusted-proof'}
   }catch{}
  }
  if($now -ge $nextPoll){$null=$socket.Send($poll,$poll.Length);$counts.Polls++;$nextPoll=$now+5000}
  $linkHealthy=($lastAck -ge 0 -and $now-$lastAck -le 15000)
  if($virt.BytesToRead -gt 0){
   foreach($b in $hostParser.Feed([Text.Encoding]::ASCII.GetBytes($virt.ReadExisting()))){
    $key=if($b -match '^[A-Z][0-9]{2,6}$'){$b}else{$b.Substring(0,[Math]::Min(3,$b.Length))+' length='+$b.Length};Count-Key $seen $key
    if($b -in @('M00','M10','R6423')){
     if($b -in @('M00','M10')){Send-Batch ($engine.Stop($now)) $true;$configured=$false;$roomVerified=$false}
     $real.Write(([char]1)+$b+([char]4))
    }elseif($b -eq 'D1V0000'){$virt.Write($idText);Count-Key $wireOut 'D1V'}
    elseif($configReply.ForQuery($b)){
     $counts.Configurations++;if($counts.Configurations -gt 3){throw 'Repeated configuration resets during voice pilot'}
     $virt.Write([Text.Encoding]::ASCII.GetString($configReply.ForQuery($b)));Reply-Frame $replies['D1P'];$configured=$true
    }elseif($b -eq 'D1B00010' -and $configured){Reply-Frame $replies['D1B']}
    elseif([CumbriaCQ.Offline.NodeDataEcho]::ForFrame($b)){
     if([CumbriaCQ.Offline.NodeRoom]::IsConnected($b,$station.OwnRoomId)){$counts.ValidOwnRoom++}else{$counts.OtherOrInvalidRoom++}
     if(!$nodeSaved){$b|ConvertTo-Json|Set-Content (Join-Path $private ('voice-node-'+$Tag+'.json'));$nodeSaved=$true}
     Send-Batch ($engine.OnClient($b,$now))
    }elseif($b -eq 'P110000'){$counts.PhysicalControlsBlocked++;Send-Batch ($engine.OnClient($b,$now))}
    elseif($b -in @('P010000','D1C0000')){
     if($configured){Send-Batch ($engine.OnClient($b,$now))}elseif($b -eq 'P010000'){Reply-Frame $idles[0]}
    }elseif($b -eq 'P100000' -or $b.StartsWith('D1E') -or $b.StartsWith('D1F0052')){
     if($configured -and $roomVerified -and $linkHealthy -and $ForwardVoice){Send-Batch ($engine.OnClient($b,$now))}
     else{$counts.GateDrops++;if($b -eq 'P100000'){Reply-Frame $idles[-1]}elseif($b.StartsWith('D1E')){try{$null=[CumbriaCQ.Offline.VoiceCodec]::ParseVoice($b);Reply-Frame 'D1E00010'}catch [ArgumentException]{Count-Key $dropped 'malformed-serial-voice'}}}
    }else{Count-Key $dropped $key}
   }
  }
  if($real.BytesToRead -gt 0){foreach($b in $realParser.Feed([Text.Encoding]::ASCII.GetBytes($real.ReadExisting()))){$kind=if($b -in @('M00','M10')){'handshake'}elseif($b -match '^R[0-9A-Fa-f]+$'){'genuine-HRI-identity'}else{$null};if($kind){Reply-Frame $b;Count-Key $hardware $kind}}}
  for($i=0;$i -lt 32 -and $socket.Available -gt 0;$i++){
   $remote=[Net.IPEndPoint]::new($receiveAny,0)
   try{$packet=$socket.Receive([ref]$remote)}catch [Net.Sockets.SocketException]{$linkHealthy=$false;break}
   if($packet.Length -eq 14 -and [Text.Encoding]::ASCII.GetString($packet,0,4) -eq 'YSFP'){$lastAck=$now;$counts.PollReplies++;$linkHealthy=$true}
   elseif($packet.Length -eq 155 -and [Text.Encoding]::ASCII.GetString($packet,0,4) -eq 'YSFD'){
    $counts.NetworkData++
    if($configured -and $roomVerified -and $linkHealthy -and $ForwardVoice){Send-Batch ($engine.OnReflector($packet,$now))}else{$counts.GateDrops++}
   }
  }
  $active=$configured -and $roomVerified -and $linkHealthy -and $ForwardVoice
  if($wasActive -and !$active){Send-Batch ($engine.Stop($now)) $true}
  Send-Batch ($engine.ControlTick($now))
  if($active){Send-Batch ($engine.Tick($now))};$wasActive=$active
  if($now-$lastStopCheck -ge 1000){
   $lastStopCheck=$now
   [pscustomobject]@{Tag=$Tag;Gateway=$station.Gateway;ElapsedMs=$now;Configured=$configured;OwnRoomVerified=$roomVerified;RoomProofReason=$proofReason;LinkHealthy=$linkHealthy;SerialReplies=$wireOut;NetworkSent=$networkOut;Counters=$counts;EngineCounts=$engine.DiagnosticCounts;Dropped=$dropped}|ConvertTo-Json -Depth 4 -Compress|Set-Content (Join-Path $root ('progress-'+$Tag+'.json'))
   if(Test-Path (Join-Path $root ('stop-'+$Tag+'.flag'))){break}
  }
  Start-Sleep -Milliseconds 10
 }
}catch{$failure=$_.Exception.Message;throw}
finally{
 if($clock -and $virt.IsOpen){try{Send-Batch ($engine.Stop($clock.ElapsedMilliseconds)) $true}catch{}}
 try{$null=$socket.Send($unlink,$unlink.Length)}catch{};$socket.Close()
 foreach($p in @($real,$virt)){if($p.IsOpen){$p.Close()};$p.Dispose()}
 $cpuEnd=[Diagnostics.Process]::GetCurrentProcess().TotalProcessorTime.TotalSeconds
 $result=[pscustomobject]@{Tag=$Tag;Gateway=$station.Gateway;HostCommands=$seen;HardwareReplies=$hardware;SerialReplies=$wireOut;NetworkSent=$networkOut;Dropped=$dropped;Counters=$counts;EngineCounts=$engine.DiagnosticCounts;Configured=$configured;OwnRoomVerified=$roomVerified;RoomProofReason=$proofReason;RoomGate='NativeMainLog:1014/PID/freshness';LinkHealthy=$linkHealthy;VoiceForwardingEnabled=[bool]$ForwardVoice;ElapsedSeconds=$(if($clock){$clock.Elapsed.TotalSeconds}else{0});CpuSeconds=($cpuEnd-$cpuStart);Error=$failure;PortsReleased=$true;PhysicalPttOn=$false;VoiceRecorded=$false}
 $result|ConvertTo-Json -Depth 5|Set-Content (Join-Path $root ('adapter-'+$Tag+'-result.json'));$result|ConvertTo-Json -Depth 5 -Compress
}
