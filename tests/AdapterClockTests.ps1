param([Parameter(Mandatory=$true)][string]$AdapterPath,[Parameter(Mandatory=$true)][string]$AssemblyPath)
$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
[Reflection.Assembly]::LoadFrom($AssemblyPath)|Out-Null
$tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseFile($AdapterPath,[ref]$tokens,[ref]$errors)
$loops=@($ast.FindAll({param($n)$n -is [Management.Automation.Language.ForEachStatementAst] -and $n.Extent.Text.StartsWith('foreach($b in $hostParser.Feed(')},$true))
if($errors.Count -or $loops.Count -ne 1){throw 'ActualSerialLoopNotFound'}
$loop=[ScriptBlock]::Create($loops[0].Extent.Text)
$senders=@($ast.FindAll({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -ceq 'Send-Batch'},$true))
if($senders.Count -ne 1){throw 'ActualBatchSenderNotFound'}
Invoke-Expression $senders[0].Extent.Text
function Check($ok,[string]$why){if(!$ok){throw $why};$script:checks++}
function Count-Key($table,$key){if(!$table.ContainsKey($key)){$table[$key]=0};$table[$key]++}
$script:checks=0;$script:time=0L;$script:acks=0;$script:packets=[Collections.Generic.List[object]]::new()
function Reply-Frame($frame){if($frame.StartsWith('P')){throw 'PhysicalControlAttempt'};if($frame -ceq 'D1E00010'){$script:acks++;$script:time+=80}}
$socket=New-Object PSObject;$socket|Add-Member ScriptMethod Send {param($p,$length)$f=New-Object byte[] 25;[Array]::Copy($p,40,$f,0,25);$info=[CumbriaCQ.Offline.YsfWire]::ReadFich($f);$script:packets.Add(@{Time=$script:time;Fi=$info[0];Packet=$p});return $length}
$clock=New-Object PSObject;$clock|Add-Member ScriptProperty ElapsedMilliseconds {$script:time}
$virt=New-Object PSObject;$virt|Add-Member ScriptMethod ReadExisting {$script:wire}
$real=New-Object PSObject;$real|Add-Member ScriptMethod Write {param($value)throw 'HardwareWrite'}
$configReply=New-Object PSObject;$configReply|Add-Member ScriptMethod ForQuery {param($value)return $null}
$hostParser=[CumbriaCQ.Offline.FrameParser]::new(512)
$engine=[CumbriaCQ.Offline.VoiceEngine]::new('TESTGW/WX',50,'D1C000B00000TEST10','B0 0    0000000',$false)
$configured=$true;$roomVerified=$true;$linkHealthy=$true;$ForwardVoice=$true;$now=0L
$seen=@{};$headerShapes=@{};$counts=@{GateDrops=0};$dropped=@{};$networkOut=@{}
$header='D1F005221016000'+'*****     '+'TESTCALL  '+(' '*40)+'09'+('0'*12)
$script:wire=([char]1)+$header+([char]4)
for($i=0;$i -lt 24;$i++){$p=New-Object byte[] 65;for($j=0;$j -lt 65;$j++){$p[$j]=[byte](($i*7+$j*3)%256)};$script:wire+=([char]1)+[CumbriaCQ.Offline.VoiceCodec]::SerialVoice('D1E',$i*5,$p)+([char]4)}
# Execute the actual parsed production serial loop with synthetic inputs only.
. $loop
Write-Output ('ClockBatch input=24 admitted='+$engine.DiagnosticCounts['transmit-voice-admitted']+' elapsed='+$script:time)
Check ($engine.DiagnosticCounts['transmit-voice-admitted'] -eq 24) 'Elapsed serial-dispatch time must not be frozen across a coalesced batch'
Check (!$engine.DiagnosticCounts.ContainsKey('transmit-queue-full')) 'Servicing elapsed deadlines must avoid artificial capacity drops'
Check ($engine.DiagnosticCounts['transmit-queue-peak'] -le 8) 'The existing hard queue bound must remain unchanged'
Check ($script:acks -eq 24) 'Every valid native voice frame must retain its ACK'
$now=$script:time;Send-Batch ($engine.OnClient('P010000',$now))
$start=$script:time
for($t=$start;$t -le $start+1000;$t+=10){$script:time=$t;$now=$t;Send-Batch ($engine.Tick($now))}
$voice=@($script:packets|Where-Object {$_.Fi -eq 1})
Check ($voice.Count -eq 24) 'All admitted frames must drain exactly once'
for($i=0;$i -lt $voice.Count;$i++){$expected=New-Object byte[] 65;for($j=0;$j -lt 65;$j++){$expected[$j]=[byte](($i*7+$j*3)%256)};$actual=[CumbriaCQ.Offline.YsfWire]::ReceiveVoice($voice[$i].Packet,50,$false);Check ([BitConverter]::ToString($actual) -ceq [BitConverter]::ToString($expected)) 'Clock refresh must preserve encoded voice bytes and order';if($i -gt 0){Check ($voice[$i].Time -gt $voice[$i-1].Time) 'Clock refresh must not create a same-instant catch-up flood'}}
Check (@($script:packets|Where-Object {$_.Fi -eq 0}).Count -eq 1) 'Clock refresh must not insert extra headers'
Check (@($script:packets|Where-Object {$_.Fi -eq 2}).Count -eq 1) 'Explicit stop must end the over exactly once'
$testVoice=[CumbriaCQ.Offline.YsfWire]::Packet('TESTGW/WX','TESTCALL',[CumbriaCQ.Offline.YsfWire]::VoiceFrame((New-Object byte[] 65),0,5,50,'TESTCALL'),1,$false)
foreach($c in @($false,$true)){foreach($r in @($false,$true)){foreach($l in @($false,$true)){foreach($f in @($false,$true)){
 $configured=$c;$roomVerified=$r;$linkHealthy=$l;$ForwardVoice=$f;$before=$script:packets.Count;$beforeAck=$script:acks
 $batch=[CumbriaCQ.Offline.BridgeBatch]::new();$batch.Network.Add($testVoice);$batch.Serial.Add('D1E00010');Send-Batch $batch
 $wanted=if($c -and $r -and $l -and $f){1}else{0}
 Check ($script:packets.Count-$before -eq $wanted) 'Network-first dispatch must retain every forwarding gate'
 Check ($script:acks-$beforeAck -eq 1) 'Forwarding gates must not remove native ACKs'
}}}}
$configured=$true;$roomVerified=$true;$linkHealthy=$true;$ForwardVoice=$true
$before=$script:packets.Count;$unsafe=[CumbriaCQ.Offline.BridgeBatch]::new();$unsafe.Network.Add($testVoice);$unsafe.Serial.Add('P100000');$rejected=$false
try{Send-Batch $unsafe}catch{$rejected=$_.Exception.Message -like '*Physical control*'}
Check ($rejected -and $script:packets.Count -eq $before) 'Physical-control preflight must reject the whole batch before network output'
Write-Output ('ADAPTER_CLOCK_PASS checks='+$script:checks+' frames='+$voice.Count+' real_dispatch=true hardware_touched=false')
