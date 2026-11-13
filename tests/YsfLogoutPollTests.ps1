param([Parameter(Mandatory=$true)][string]$Bin,[Parameter(Mandatory=$true)][string]$AdapterPath)
$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
[Reflection.Assembly]::LoadFrom((Join-Path $Bin 'BridgeConfigCore.dll'))|Out-Null
$tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseFile($AdapterPath,[ref]$tokens,[ref]$errors)
$polling=@($ast.FindAll({param($n)$n -is [Management.Automation.Language.IfStatementAst] -and $n.Extent.Text.StartsWith('if($now -ge $nextPoll)')},$true));if($polling.Count -ne 1){throw 'ActualPollSenderNotFound'}
function Count-Key($table,$key){if(!$table.ContainsKey($key)){$table[$key]=0};$table[$key]++}
$old=[Net.Sockets.UdpClient]::new([Net.IPEndPoint]::new([Net.IPAddress]::Loopback,0));$next=[Net.Sockets.UdpClient]::new([Net.IPEndPoint]::new([Net.IPAddress]::Loopback,0));$socket=[Net.Sockets.UdpClient]::new([Net.Sockets.AddressFamily]::InterNetwork);$old.Client.ReceiveTimeout=1000
try{
 $settings=[CumbriaCQ.Configuration.SettingsStore]::Defaults();$settings.YsfHost='127.0.0.1';$settings.YsfPort=$old.Client.LocalEndPoint.Port;$socket.Connect([Net.IPAddress]::Loopback,$settings.YsfPort);$ysfReload=[CumbriaCQ.Configuration.LiveYsfLink]::new($socket,$settings,[Net.IPAddress]::Loopback,'TESTGW/WX');$ysfReload.ObserveAck(0)
 $wanted=[CumbriaCQ.Configuration.SettingsStore]::Defaults();$wanted.YsfHost='127.0.0.1';$wanted.YsfPort=$next.Client.LocalEndPoint.Port;$wanted.YsfRoomId='00016';$ysfReload.Request($wanted,[Guid]::NewGuid().ToString('N'),100);$ysfReload.Advance(100,$true)
 if($ysfReload.State -cne 'Unlinking' -or !$ysfReload.Paused){throw 'LogoutMustBeAnExplicitPausedPhase'}
 $now=100L;$nextPoll=0L;$poll=[Text.Encoding]::ASCII.GetBytes('YSFPTESTGW/WX ');$counts=@{Polls=0};$dropped=@{};. ([ScriptBlock]::Create($polling[0].Extent.Text))
 $polls=0;$unlinks=0;while($old.Available -gt 0){$peer=[Net.IPEndPoint]::new([Net.IPAddress]::Any,0);$p=$old.Receive([ref]$peer);$tag=[Text.Encoding]::ASCII.GetString($p,0,4);if($tag -ceq 'YSFP'){$polls++}elseif($tag -ceq 'YSFU'){$unlinks++}}
 if($polls -ne 0 -or $counts.Polls -ne 0){throw 'Old-room keepalives must stop during logout; a poll registers the old room again'}
 if($unlinks -ne 1 -or $next.Available -ne 0){throw 'LogoutMustPrecedeNewRoomJoin'}
 $ysfReload.ObserveAck(150);if($ysfReload.IsHealthy(150)){throw 'A late old-room ACK must not reopen forwarding during logout'}
 'YSF_LOGOUT_POLL_PASS checks=4 actual_adapter_poll=true real_loopback_udp=true native_touched=false'
}finally{$socket.Close();$old.Close();$next.Close()}
