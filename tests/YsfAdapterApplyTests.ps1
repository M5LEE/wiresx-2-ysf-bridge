param([Parameter(Mandatory=$true)][string]$AdapterPath,[Parameter(Mandatory=$true)][string]$Bin,[Parameter(Mandatory=$true)][string]$Fixture)
$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseFile($AdapterPath,[ref]$tokens,[ref]$errors)
$functions=@($ast.FindAll({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -ceq 'Update-YsfApply'},$true))
if($functions.Count -ne 1){Write-Output 'Live YSF apply must be wired into the actual adapter loop';exit 1}
[Reflection.Assembly]::LoadFrom((Join-Path $Bin 'BridgeProtocol.dll'))|Out-Null
[Reflection.Assembly]::LoadFrom((Join-Path $Bin 'BridgeConfigCore.dll'))|Out-Null
Invoke-Expression $functions[0].Extent.Text
$script:checks=0
function Check($ok,$why){if(!$ok){throw $why};$script:checks++}
function Send-Batch($batch,[bool]$endingOnly=$false){if($batch.Network.Count -gt 0){throw 'Old-room speech must not cross a handover'};foreach($frame in $batch.Serial){if($frame.StartsWith('P')){throw 'PhysicalControl'}}}
function Start-Process{throw 'Restart attempted'};function Stop-Process{throw 'Restart attempted'}
$root=[IO.Path]::GetFullPath($Fixture);[IO.Directory]::CreateDirectory((Join-Path $root 'launcher-state'))|Out-Null
$Tag='bridge'+('b'*32);$adapterStartUtc=(Get-Process -Id $PID).StartTime.ToUniversalTime().ToString('o')
$settings=[CumbriaCQ.Configuration.SettingsStore]::Defaults();$settings.YsfHost='127.0.0.1'
$old=[Net.Sockets.UdpClient]::new([Net.IPEndPoint]::new([Net.IPAddress]::Loopback,0));$next=[Net.Sockets.UdpClient]::new([Net.IPEndPoint]::new([Net.IPAddress]::Loopback,0));$old.Client.ReceiveTimeout=1500;$next.Client.ReceiveTimeout=1500
$settings.YsfPort=$old.Client.LocalEndPoint.Port;$socket=[Net.Sockets.UdpClient]::new([Net.Sockets.AddressFamily]::InterNetwork);$socket.Connect([Net.IPAddress]::Loopback,$settings.YsfPort);$socket.Client.ReceiveTimeout=1500
$ysfReload=[CumbriaCQ.Configuration.LiveYsfLink]::new($socket,$settings,[Net.IPAddress]::Loopback,'TESTGW/WX');$ysfReload.ObserveAck(0)
$engine=[CumbriaCQ.Offline.VoiceEngine]::new('TESTGW/WX',50,'D1C000B00000TEST10','B0 0    0000000',$false)
$lastNativeVoice=0L;$lastYsfVoice=-10000L;$lastYsfCheck=-1000L;$ysfLastRequest='';$ysfApplyError='';$ysfApplyErrorId='';$linkHealthy=$true;$counts=@{}
try{
 $id=@{Pid=$PID;Created=$adapterStartUtc;Root=$root;Tag=$Tag};@{Root=$root;Tag=$Tag;State='Running';Adapter=$id}|ConvertTo-Json|Set-Content (Join-Path $root 'launcher-state\owner.json')
 @{Tag=$Tag;AdapterPid=$PID;AdapterStartUtc=$adapterStartUtc;YsfApplyVersion=1;YsfProgramRoot=$Bin}|ConvertTo-Json|Set-Content (Join-Path $root ('progress-'+$Tag+'.json'))
 $wanted=[CumbriaCQ.Configuration.SettingsStore]::Defaults();$wanted.YsfHost='127.0.0.1';$wanted.YsfPort=$next.Client.LocalEndPoint.Port;$wanted.YsfRoomId='00016';$wanted.DgId=25
 $null=[CumbriaCQ.Configuration.SettingsStore]::Save((Join-Path $root 'bridge-config.json'),$wanted,'MISSING');$request=[CumbriaCQ.Configuration.YsfApplyStore]::Submit($root,$Bin)
 $header='D1F005221016000'+'*****     '+'TESTCALL  '+(' '*40)+'09'+('0'*12);$null=$engine.OnClient($header,0);$null=$engine.OnClient([CumbriaCQ.Offline.VoiceCodec]::SerialVoice('D1E',0,(New-Object byte[] 65)),1)
 Update-YsfApply 100
 Check ($ysfReload.State -ceq 'WaitingForIdle' -and $old.Available -eq 0 -and $linkHealthy) 'The actual adapter must keep the old link during an over'
 $null=$engine.OnClient('P010000',100);$null=$engine.Tick(101);Update-YsfApply 1200
 $peer=[Net.IPEndPoint]::new([Net.IPAddress]::Any,0);$bye=$old.Receive([ref]$peer);Check ([Text.Encoding]::ASCII.GetString($bye,0,4) -ceq 'YSFU' -and $ysfReload.State -ceq 'Unlinking' -and $next.Available -eq 0) 'The adapter must log out only after the idle boundary and before joining the new room';Update-YsfApply 1450;$null=$old.Receive([ref]$peer);Update-YsfApply 1700;$null=$old.Receive([ref]$peer);Update-YsfApply 1950;$poll=$next.Receive([ref]$peer);Check (!$linkHealthy) 'Handover must close the voice gate before acknowledgement'
 $null=$next.Send($poll,$poll.Length,$peer);$any=[Net.IPEndPoint]::new([Net.IPAddress]::Any,0);$null=$socket.Receive([ref]$any);$ysfReload.ObserveAck(1960);Update-YsfApply 1960
 Check ($ysfReload.State -ceq 'Applied' -and $linkHealthy -and $settings.YsfRoomId -ceq '00016' -and $settings.DgId -eq 25) 'The actual adapter must apply the acknowledged settings without a restart'
 $null=$engine.OnClient($header,2000);$b=$engine.OnClient([CumbriaCQ.Offline.VoiceCodec]::SerialVoice('D1E',0,(New-Object byte[] 65)),2001);$f=New-Object byte[] 25;[Array]::Copy($b.Network[0],40,$f,0,25);Check ([CumbriaCQ.Offline.YsfWire]::ReadFich($f)[4] -eq 25) 'The real engine must use the applied DG-ID on the next header'
 $udp=@($ast.FindAll({param($n)$n -is [Management.Automation.Language.ForStatementAst] -and $n.Extent.Text.StartsWith('for($i=0;$i -lt 32 -and $socket.Available')},$true));Check ($udp.Count -eq 1) 'The actual UDP receive loop must be tested'
 $actualSocket=$socket;$script:queuedOld=$true;$socket=New-Object PSObject;$socket|Add-Member ScriptProperty Available {if($script:queuedOld){14}else{0}};$socket|Add-Member ScriptMethod Receive {param($remote)$script:queuedOld=$false;$remote.Value=[Net.IPEndPoint]::new([Net.IPAddress]::Loopback,$old.Client.LocalEndPoint.Port);return [Text.Encoding]::ASCII.GetBytes('YSFPTESTGW/WX ')}
 $receiveAny=[Net.IPAddress]::Any;$clock=New-Object PSObject -Property @{ElapsedMilliseconds=1400L};$counts.PollReplies=0;$dropped=@{};function Count-Key($table,$key){if(!$table.ContainsKey($key)){$table[$key]=0};$table[$key]++}
 try{. ([ScriptBlock]::Create($udp[0].Extent.Text));Check ($counts.PollReplies -eq 0) 'An old-peer datagram queued before reconnect must not acknowledge the new YSF destination'}finally{$socket=$actualSocket}
 $polling=@($ast.FindAll({param($n)$n -is [Management.Automation.Language.IfStatementAst] -and $n.Extent.Text.StartsWith('if($now -ge $nextPoll)')},$true));Check ($polling.Count -eq 1) 'The actual poll sender must be tested'
 $socket=New-Object PSObject;$socket|Add-Member ScriptMethod Send {param($packet,$length)throw [Net.Sockets.SocketException]::new(10054)};$now=2000L;$nextPoll=0L;$poll=[Text.Encoding]::ASCII.GetBytes('YSFPTESTGW/WX ');$failed=$false
 try{try{. ([ScriptBlock]::Create($polling[0].Extent.Text))}catch{$failed=$true;Write-Output ('POLL_TEST_EXCEPTION '+$_.Exception.GetType().FullName+' '+$_.Exception.GetBaseException().GetType().FullName+' '+$_.Exception.Message)};Check (!$failed) 'A UDP handover poll failure must not end the adapter or restart WIRES-X';Check (!$ysfReload.IsHealthy($now)) 'A transport error must revoke stale link health'}finally{$socket=$actualSocket}
 Write-Output ('YSF_ADAPTER_APPLY_PASS checks='+$checks+' actual_function=true real_loopback_udp=true native_restarted=false')
}finally{$socket.Close();$old.Close();$next.Close()}
