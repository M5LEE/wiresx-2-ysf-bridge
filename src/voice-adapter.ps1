param([ValidateRange(60,18000)][int]$Seconds=600,[string]$Tag='voicepilot',[switch]$ForwardVoice,[ValidateSet('BridgeProtocol.dll')][string]$AssemblyName='BridgeProtocol.dll',[switch]$UntilStopped)
# Experimental current-room bridge. Physical hardware sees M00/M10/R6423 only.
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
# Current room and emulated-radio identity are derived from native state, not configured.
$real=New-Object IO.Ports.SerialPort $station.PhysicalPort,38400,([IO.Ports.Parity]::None),8,([IO.Ports.StopBits]::One)
$virt=New-Object IO.Ports.SerialPort $station.AdapterPort,38400,([IO.Ports.Parity]::None),8,([IO.Ports.StopBits]::One)
foreach($p in @($real,$virt)){$p.DtrEnable=$false;$p.RtsEnable=$false;$p.Handshake='None';$p.WriteTimeout=500}
$hostParser=[CumbriaCQ.Offline.FrameParser]::new(1024);$realParser=[CumbriaCQ.Offline.FrameParser]::new(1024)
$addresses=@([Net.Dns]::GetHostAddresses($settings.YsfHost))
$address=@($addresses|Where-Object {$_.AddressFamily -eq [Net.Sockets.AddressFamily]::InterNetwork})[0]
if(!$address){$address=@($addresses|Where-Object {$_.AddressFamily -eq [Net.Sockets.AddressFamily]::InterNetworkV6})[0]}
if(!$address){throw 'Reflector host has no supported IP address'}
$socket=[Net.Sockets.UdpClient]::new($address.AddressFamily);$socket.Client.ReceiveTimeout=500;$socket.Connect($address,$settings.YsfPort)
$ysfReload=[CumbriaCQ.Configuration.LiveYsfLink]::new($socket,$settings,$address,$station.Gateway)
$adapterStartUtc=(Get-Process -Id $PID).StartTime.ToUniversalTime().ToString('o')
$lastNativeVoice=-10000L;$lastYsfVoice=-10000L;$lastYsfCheck=-1000L;$ysfLastRequest='';$ysfApplyError='';$ysfApplyErrorId=''
$receiveAny=if($address.AddressFamily -eq [Net.Sockets.AddressFamily]::InterNetworkV6){[Net.IPAddress]::IPv6Any}else{[Net.IPAddress]::Any}
$poll=[Text.Encoding]::ASCII.GetBytes('YSFP'+$station.Gateway.PadRight(10));$unlink=[Text.Encoding]::ASCII.GetBytes('YSFU'+$station.Gateway.PadRight(10))
$configured=$false;$roomVerified=$false;$linkHealthy=$false;$wasActive=$false;$nodeSaved=$false;$proofReason='not-yet-read'
$currentRoom=$null;$connectionKey=$null;$roomBarrier=$null
$resetGuard=[CumbriaCQ.Offline.ConfigurationResetGuard]::new()
$seen=@{};$hardware=@{};$wireOut=@{};$networkOut=@{};$dropped=@{};$headerShapes=@{};$counts=@{Polls=0;PollReplies=0;ValidOwnRoom=0;OtherOrInvalidRoom=0;NetworkData=0;GateDrops=0;PhysicalControlsBlocked=0;Configurations=0}
$failure=$null;$nextPoll=0;$lastStopCheck=0;$lastProofCheck=-1000;$clock=$null;$cpuStart=0
function Count-Key($table,$key){if(!$table.ContainsKey($key)){$table[$key]=0};$table[$key]++}
function Write-ProgressSnapshot([string]$Path,[string]$Json){
 $temp=$Path+'.'+[Guid]::NewGuid().ToString('N')+'.pending'
 try{
  [IO.File]::WriteAllText($temp,$Json,[Text.UTF8Encoding]::new($false))
  if([IO.File]::Exists($Path)){[IO.File]::Replace($temp,$Path,[NullString]::Value)}else{[IO.File]::Move($temp,$Path)}
  return $true
 }catch [IO.IOException]{return $false}
 catch [UnauthorizedAccessException]{return $false}
 finally{if([IO.File]::Exists($temp)){try{[IO.File]::Delete($temp)}catch [IO.IOException]{}catch [UnauthorizedAccessException]{}}}
}
function Reply-Frame([string]$body){$virt.Write(([char]1)+$body+([char]4));$key=$body.Substring(0,[Math]::Min(3,$body.Length));Count-Key $wireOut $key}
function Send-Batch($batch,[bool]$endingOnly=$false){
 foreach($frame in $batch.Serial){if($frame.StartsWith('P')){throw 'Physical control in software response output'}}
 # Do not hold already-due voice behind a potentially blocking serial ACK.
 foreach($packet in $batch.Network){
  if($ForwardVoice -and (($configured -and $roomVerified -and $linkHealthy) -or ($endingOnly -and (($packet[34] -band 1) -eq 1)))){
   $null=$socket.Send($packet,$packet.Length);Count-Key $networkOut 'YSFD';if(($packet[34] -band 1) -ne 0){Count-Key $networkOut 'EOT'}
  }else{Count-Key $dropped 'network-output-gated'}
 }
 foreach($frame in $batch.Serial){Reply-Frame $frame}
}
function Update-YsfApply([long]$now){
 if($now-$script:lastYsfCheck -ge 1000){
  $script:lastYsfCheck=$now
  try{
   $request=[CumbriaCQ.Configuration.YsfApplyStore]::ReadForAdapter($root,$Tag,$PID,$adapterStartUtc,$ysfLastRequest)
   if($request){
    $script:ysfLastRequest=$request.RequestId;$script:ysfApplyErrorId=$request.RequestId
    $ysfReload.Request($request.Settings,$request.RequestId,$now);$script:ysfApplyError=''
   }
  }catch{$script:ysfApplyError=$_.Exception.GetBaseException().Message}
 }
 $oldRevision=$ysfReload.Revision;$oldTransport=$ysfReload.TransportGeneration
 $quiet=$engine.CanChangeYsf($now) -and $now-$lastNativeVoice -ge 1000 -and $now-$lastYsfVoice -ge 1000
 $ysfReload.Advance($now,$quiet)
 if($ysfReload.TransportGeneration -ne $oldTransport){Send-Batch ($engine.Stop($now)) $true}
 if($ysfReload.Revision -ne $oldRevision){
  $next=$ysfReload.ActiveSettings;$engine.SetYsfOptions($next.DgId,$next.AllowZeroDg);$script:settings=$next
 }
 $script:linkHealthy=$ysfReload.IsHealthy($now)
}
try{
 if(Get-Process Wires-X -ErrorAction SilentlyContinue){throw 'Start adapter before WIRES-X'}
 $real.Open();$virt.Open();Start-Sleep -Seconds 7
 'ADAPTER_READY;EXPERIMENTAL_VOICE=True;PHYSICAL_TRANSMIT=False;ROOM_GATE=CURRENT_NATIVE_CONNECTION'
 $clock=[Diagnostics.Stopwatch]::StartNew();$cpuStart=[Diagnostics.Process]::GetCurrentProcess().TotalProcessorTime.TotalSeconds
 while($UntilStopped -or $clock.Elapsed.TotalSeconds -lt $Seconds){
  $now=$clock.ElapsedMilliseconds
  if($now-$lastProofCheck -ge 1000){
   $lastProofCheck=$now;$roomVerified=$false;$proofReason='missing-or-invalid';$nextRoom=$null;$nextKey=$null
   try{
    $proof=Get-Content (Join-Path $root ('room-proof-'+$Tag+'.json')) -Raw -ErrorAction Stop|ConvertFrom-Json
    $age=([DateTime]::UtcNow-[DateTime]::Parse($proof.Utc).ToUniversalTime()).TotalSeconds
    $app=Get-Process Wires-X -ErrorAction Stop
    $roomVerified=($proof.Tag -ceq $Tag -and $proof.Method -ceq 'NativeMainLog' -and $proof.ControlId -eq 1014 -and $proof.AppPid -eq $app.Id -and $proof.AppStartUtc -ceq $app.StartTime.ToUniversalTime().ToString('o') -and $proof.Connected -eq $true -and $proof.RoomId -cmatch '^[0-9]{5}$' -and $proof.RoomId -cne '00000' -and $proof.ConnectionKey -and $proof.ConnectionKey -cne $roomBarrier -and $age -ge 0 -and $age -le 8 -and !$proof.Error)
    if($roomVerified){$nextRoom=$proof.RoomId;$nextKey=$proof.ConnectionKey}
    $proofReason=if($roomVerified){'verified'}elseif($age -gt 8 -or $age -lt 0){'stale'}elseif($proof.AppPid -ne $app.Id){'different-process'}elseif($proof.Error){'observer-error'}else{'not-connected-or-untrusted-proof'}
   }catch{}
   if($nextKey -cne $connectionKey){
    Send-Batch ($engine.Stop($now)) $true
    Send-Batch ($engine.SetConnectedRoom($nextRoom,$now)) $true
    $currentRoom=$nextRoom;$connectionKey=$nextKey
   }
  }
  if($now -ge $nextPoll){if($ysfReload.CanPoll){try{$null=$socket.Send($poll,$poll.Length);$counts.Polls++}catch{if($_.Exception.GetBaseException() -isnot [Net.Sockets.SocketException]){throw};$ysfReload.ObserveTransportError();Count-Key $dropped 'ysf-poll-socket-error'};$nextPoll=$now+5000}}
  $linkHealthy=$ysfReload.IsHealthy($now)
  if($virt.BytesToRead -gt 0){
   foreach($b in $hostParser.Feed([Text.Encoding]::ASCII.GetBytes($virt.ReadExisting()))){
    # Serial ACK/dispatch can span a playout deadline within one parsed batch.
    $now=$clock.ElapsedMilliseconds
    $key=if($b -match '^[A-Z][0-9]{2,6}$'){$b}else{$b.Substring(0,[Math]::Min(3,$b.Length))+' length='+$b.Length};Count-Key $seen $key
    # Command/declared length/mode only: no callsign, GPS or voice payload retained.
    if($b -match '^D1F[0-9A-F]{12}'){Count-Key $headerShapes ($b.Substring(0,15)+' length='+$b.Length)}
    if($b -in @('M00','M10','R6423')){
     if($b -in @('M00','M10')){Send-Batch ($engine.Stop($now)) $true;$configured=$false;$roomVerified=$false}
     $real.Write(([char]1)+$b+([char]4))
    }elseif($b -eq 'D1V0000'){$virt.Write($idText);Count-Key $wireOut 'D1V'}
    elseif($configReply.ForQuery($b)){
     $counts.Configurations++;if(!$resetGuard.Allow($now)){throw 'Repeated configuration resets within 60 seconds'}
     $virt.Write([Text.Encoding]::ASCII.GetString($configReply.ForQuery($b)));Reply-Frame $replies['D1P'];$configured=$true
    }elseif($b -eq 'D1B00010' -and $configured){Reply-Frame $replies['D1B']}
    elseif([CumbriaCQ.Offline.NodeDataEcho]::ForFrame($b)){
     if($currentRoom -and [CumbriaCQ.Offline.NodeRoom]::IsConnected($b,$currentRoom)){$counts.ValidOwnRoom++}else{
      $counts.OtherOrInvalidRoom++
      if($currentRoom){$roomBarrier=$connectionKey;$roomVerified=$false;Send-Batch ($engine.Stop($now)) $true}
     }
     if(!$nodeSaved){$b|ConvertTo-Json|Set-Content (Join-Path $private ('voice-node-'+$Tag+'.json'));$nodeSaved=$true}
     Send-Batch ($engine.OnClient($b,$now))
    }elseif($b -eq 'P110000'){$counts.PhysicalControlsBlocked++;Send-Batch ($engine.OnClient($b,$now))}
    elseif($b -in @('P010000','D1C0000')){
     if($configured){Send-Batch ($engine.OnClient($b,$now))}elseif($b -eq 'P010000'){Reply-Frame $idles[0]}
    }elseif($b.StartsWith('D1F0052') -or (('CumbriaCQ.Offline.TransmitMetadata' -as [type]) -and [CumbriaCQ.Offline.TransmitMetadata]::SourceForFrame($b))){
     # Metadata ACK is radio-link flow control, not permission to forward voice.
     # Keep it responsive even while the independent network/room gate is closed.
     Send-Batch ($engine.OnClient($b,$now))
    }elseif($b -eq 'P100000' -or $b.StartsWith('D1E')){
     if($b.StartsWith('D1E')){$lastNativeVoice=$now}
     if($configured -and $roomVerified -and $linkHealthy -and $ForwardVoice){Send-Batch ($engine.OnClient($b,$now))}
     else{$counts.GateDrops++;if($b -eq 'P100000'){Reply-Frame $idles[-1]}elseif($b.StartsWith('D1E')){try{$null=[CumbriaCQ.Offline.VoiceCodec]::ParseVoice($b);Reply-Frame 'D1E00010'}catch [ArgumentException]{Count-Key $dropped 'malformed-serial-voice'}}}
    }else{Count-Key $dropped $key}
   }
  }
  if($real.BytesToRead -gt 0){foreach($b in $realParser.Feed([Text.Encoding]::ASCII.GetBytes($real.ReadExisting()))){$kind=if($b -in @('M00','M10')){'handshake'}elseif($b -match '^R[0-9A-Fa-f]+$'){'genuine-HRI-identity'}else{$null};if($kind){Reply-Frame $b;Count-Key $hardware $kind}}}
  for($i=0;$i -lt 32 -and $socket.Available -gt 0;$i++){
   $now=$clock.ElapsedMilliseconds
   $remote=[Net.IPEndPoint]::new($receiveAny,0)
   try{$packet=$socket.Receive([ref]$remote)}catch{if($_.Exception.GetBaseException() -isnot [Net.Sockets.SocketException]){throw};$ysfReload.ObserveTransportError();$linkHealthy=$false;break}
   if($remote.Address.ToString() -cne $ysfReload.PeerAddress -or $remote.Port -ne $ysfReload.PeerPort){Count-Key $dropped 'old-peer-datagram';continue}
   if($packet.Length -eq 14 -and [Text.Encoding]::ASCII.GetString($packet,0,4) -eq 'YSFP'){$ysfReload.ObserveAck($now);$counts.PollReplies++;$linkHealthy=$ysfReload.IsHealthy($now)}
   elseif($packet.Length -eq 155 -and [Text.Encoding]::ASCII.GetString($packet,0,4) -eq 'YSFD'){
    $lastYsfVoice=$now
    $counts.NetworkData++
    if($configured -and $roomVerified -and $linkHealthy -and $ForwardVoice){Send-Batch ($engine.OnReflector($packet,$now))}else{$counts.GateDrops++}
   }
  }
  $now=$clock.ElapsedMilliseconds
  $active=$configured -and $roomVerified -and $linkHealthy -and $ForwardVoice
  if($wasActive -and !$active){Send-Batch ($engine.Stop($now)) $true}
  Send-Batch ($engine.ControlTick($now))
  if($active){Send-Batch ($engine.Tick($now))};$wasActive=$active
  Update-YsfApply $clock.ElapsedMilliseconds
  if($now-$lastStopCheck -ge 1000){
   $lastStopCheck=$now
   $snapshot=[pscustomobject]@{Tag=$Tag;Gateway=$station.Gateway;ElapsedMs=$now;Configured=$configured;OwnRoomVerified=$roomVerified;RoomProofReason=$proofReason;LinkHealthy=$linkHealthy;SerialReplies=$wireOut;NetworkSent=$networkOut;Counters=$counts;EngineCounts=$engine.DiagnosticCounts;Dropped=$dropped;HeaderShapes=$headerShapes;YsfApplyVersion=1;AdapterPid=$PID;AdapterStartUtc=$adapterStartUtc;YsfProgramRoot=$script:Bin;YsfActive=$ysfReload.ActiveSettings;YsfEndpoint=@{Address=$ysfReload.PeerAddress;Port=$ysfReload.PeerPort;LocalPort=$socket.Client.LocalEndPoint.Port;Revision=$ysfReload.Revision;Paused=$ysfReload.Paused};YsfApply=@{RequestId=$ysfReload.RequestId;State=$ysfReload.State;Message=$ysfReload.Message;Pending=$ysfReload.Pending;ErrorRequestId=$ysfApplyErrorId;Error=$ysfApplyError}}|ConvertTo-Json -Depth 5 -Compress
   if(!(Write-ProgressSnapshot (Join-Path $root ('progress-'+$Tag+'.json')) $snapshot)){Count-Key $counts 'ProgressWriteFailures'}
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
 $result=[pscustomobject]@{Tag=$Tag;Gateway=$station.Gateway;HostCommands=$seen;HardwareReplies=$hardware;SerialReplies=$wireOut;NetworkSent=$networkOut;Dropped=$dropped;HeaderShapes=$headerShapes;Counters=$counts;EngineCounts=$engine.DiagnosticCounts;Configured=$configured;OwnRoomVerified=$roomVerified;RoomProofReason=$proofReason;RoomGate='NativeMainLog:1014/PID/freshness';LinkHealthy=$linkHealthy;VoiceForwardingEnabled=[bool]$ForwardVoice;ElapsedSeconds=$(if($clock){$clock.Elapsed.TotalSeconds}else{0});CpuSeconds=($cpuEnd-$cpuStart);Error=$failure;PortsReleased=$true;PhysicalPttOn=$false;VoiceRecorded=$false}
 $result|ConvertTo-Json -Depth 5|Set-Content (Join-Path $root ('adapter-'+$Tag+'-result.json'));$result|ConvertTo-Json -Depth 5 -Compress
}
