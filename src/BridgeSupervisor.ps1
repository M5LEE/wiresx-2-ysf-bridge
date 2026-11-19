[CmdletBinding()]
param([switch]$Capture,[switch]$Start,[switch]$Stop,[switch]$Recover,[switch]$CheckOnly,[switch]$SelfTest,[switch]$UntilStopped)
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
. (Join-Path $PSScriptRoot 'PublicRuntime.ps1')
$script:NativeHash='8F05DC26794144438566B880CE775F5178D62EB3C4DEB8C053089216342BC671'
function Emit($event,$data) { [pscustomobject]@{Event=$event;Data=$data}|ConvertTo-Json -Depth 8 -Compress|Write-Output }
function Identity($p) { @{Pid=$p.Id;Created=$p.StartTime.ToUniversalTime().ToString('o');Root=$script:Root;Tag=$script:Tag} }
function Matching($i) {
    if(!$i -or $i.Root -cne $script:Root -or $i.Tag -cne $script:Tag){return $null}
    $p=Get-Process -Id $i.Pid -ErrorAction SilentlyContinue
    if($p -and $p.StartTime.ToUniversalTime().ToString('o') -ceq $i.Created){return $p}
    return $null
}
function Save-Owner {
    Assert-DataPath $script:Manifest
    $tmp=$script:Manifest+'.pending';Assert-DataPath $tmp
    $script:Owner|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $tmp -Encoding UTF8
    Move-Item -LiteralPath $tmp -Destination $script:Manifest -Force
}
function Assert-NoAdapter {
    # Read-only global detection; intentionally not limited to this root/tag.
    $a=@(Find-BridgeAdapters)
    if($a.Count){throw 'ExistingAdapter'}
}
function Exact-Processes($name,$path) {
    $ps=@(Get-Process -Name $name -ErrorAction SilentlyContinue)
    foreach($p in $ps){if($p.Path -ine $path){throw 'UnverifiedExecutablePath'}}
    return $ps
}
function Close-Exact($p,[bool]$force=$false) {
    $i=Identity $p
    $null=$p.CloseMainWindow()
    if(!$p.WaitForExit(10000)){
        if(!$force){throw 'GracefulNativeExitIncomplete'}
        $q=Matching $i
        if($q){Stop-Process -Id $q.Id -ErrorAction Stop;$q.WaitForExit(5000)|Out-Null}
    }
    if(Matching $i){throw 'OwnedProcessStillAlive'}
}
function Load-Aliases {
    $b=Get-Content -LiteralPath (Join-Path $script:Root 'discovery-name-backup.json') -Raw|ConvertFrom-Json
    # Only the two discovery endpoints in the backup, never enumerate/write other devices.
    if($b.Count -ne 2 -or @($b.Path|Select-Object -Unique).Count -ne 2){throw 'AliasBackupScope'}
    $result=@();$ports=@()
    foreach($x in $b){
        if($x.Path -notmatch '^HKLM:\\SYSTEM\\CurrentControlSet\\Enum\\[^\r\n]+$' -or $x.Path -match '\.\.' -or $x.FriendlyName -notmatch '\((COM[1-9][0-9]{0,3})\)$'){throw 'AliasBackupScope'}
        $port=$Matches[1];$ports+=$port
        if(($port -ceq $script:Station.NativePort) -ne ($x.Path -like '*\COM0COM\*')){throw 'AliasBackupScope'}
        $alias=if($port -ceq $script:Station.NativePort){'HRI-200 Communication device A ('+$port+')'}else{'WIRESX to YSF physical HRI ('+$port+')'}
        if((Get-ItemProperty -LiteralPath $x.Path -Name FriendlyName).FriendlyName -cne $x.FriendlyName){throw 'AliasBaselineMismatch'}
        $result+=@{Path=$x.Path;Original=$x.FriendlyName;Alias=$alias;Pending=$false}
    }
    if((($ports|Sort-Object) -join ',') -cne ((@($script:Station.PhysicalPort,$script:Station.NativePort)|Sort-Object) -join ',')){throw 'AliasBackupScope'}
    return $result
}
function Apply-Aliases {
    foreach($x in $script:Owner.Aliases){
        if(Get-Process -Name Wires-X -ErrorAction SilentlyContinue){throw 'NativeBeforeAliasChange'}
        if((Get-ItemProperty -LiteralPath $x.Path -Name FriendlyName).FriendlyName -cne $x.Original){throw 'AliasBaselineMismatch'}
        # Persist intent BEFORE write, including partial failures.
        $x.Pending=$true;Save-Owner
        Set-ItemProperty -LiteralPath $x.Path -Name FriendlyName -Value $x.Alias
        if((Get-ItemProperty -LiteralPath $x.Path -Name FriendlyName).FriendlyName -cne $x.Alias){throw 'AliasWriteVerification'}
    }
}
function Spawn-Script($name,$arguments,[string]$stdout='') {
    $path=Join-Path $script:Bin $name
    $argsLine='-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+$path+'" '+$arguments
    $opts=@{FilePath=(Join-Path $PSHOME 'powershell.exe');ArgumentList=$argsLine;WorkingDirectory=$script:Root;PassThru=$true;WindowStyle='Hidden'}
    if($stdout){$opts.RedirectStandardOutput=$stdout;$opts.RedirectStandardError=($stdout+'.error')}
    return Start-Process @opts
}
function Owned-Flag($prefix) {
    $flag=Join-Path $script:Root ($prefix+$script:Tag+'.flag');Assert-DataPath $flag
    [IO.File]::WriteAllText($flag,'stop')
}
function Cleanup-Real {
    $errors=New-Object 'System.Collections.Generic.List[string]'
    # Each cleanup is independent: one failure must not skip another resource.
    foreach($kind in @('Adapter','Observer','Native')){
        try{
            $p=Matching $script:Owner[$kind]
            if($p){
                if($kind -eq 'Adapter'){Owned-Flag 'stop-'}
                if($kind -eq 'Observer'){Owned-Flag 'observer-stop-'}
                if($kind -eq 'Native'){Close-Exact $p $true}
                elseif(!$p.WaitForExit(12000)){
                    $q=Matching $script:Owner[$kind]
                    if($q){Stop-Process -Id $q.Id;$q.WaitForExit(5000)|Out-Null}
                }
                if(Matching $script:Owner[$kind]){throw 'StillAlive'}
            }
        }catch{$errors.Add('Cleanup'+$kind)}
    }
    foreach($x in $script:Owner.Aliases){
        if(!$x.Pending){continue}
        try{
            if(Get-Process -Name Wires-X -ErrorAction SilentlyContinue){throw 'NativeStillPresent'}
            $current=(Get-ItemProperty -LiteralPath $x.Path -Name FriendlyName).FriendlyName
            if($current -ceq $x.Alias){Set-ItemProperty -LiteralPath $x.Path -Name FriendlyName -Value $x.Original}
            elseif($current -cne $x.Original){throw 'AliasOwnershipLost'}
            if((Get-ItemProperty -LiteralPath $x.Path -Name FriendlyName).FriendlyName -cne $x.Original){throw 'RestoreVerification'}
            $x.Pending=$false;Save-Owner
        }catch{$errors.Add('CleanupAlias')}
    }
    if($errors.Count){$script:Owner.State='CleanupFailed';Save-Owner;throw ($errors -join ',')}
    $script:Owner.State='Stopped';Save-Owner
    Remove-Item -LiteralPath $script:Manifest
}
# Same orchestration for real dependencies and isolated fake dependencies.
function Invoke-Lifecycle($ops,[int]$readyTicks=120,[int]$runTicks=72000,[bool]$untilStopped=$false) {
    try {
        & $ops.Preflight
        & $ops.Prepare
        & $ops.Adapter
        $ready=$false
        for($n=0;$n -lt $readyTicks;$n++){
            if(& $ops.Stop){return 'StopRequested'}
            if(!(& $ops.Alive)){throw 'AdapterExitedBeforeReady'}
            if(& $ops.Ready){$ready=$true;break}
            & $ops.Tick
        }
        if(!$ready){throw 'AdapterReadyTimeout'}
        & $ops.Native
        if(!(& $ops.Alive)){throw 'AdapterExitedBeforeObserver'}
        & $ops.Observer
        for($n=0;$untilStopped -or $n -lt $runTicks;$n++){
            if(& $ops.Stop){return 'StopRequested'}
            if(!(& $ops.Alive)){if($Capture){return 'CaptureComplete'};throw 'AdapterExited'}
            if(!(& $ops.Healthy)){throw 'ChildExited'}
            & $ops.Tick
        }
        return 'RuntimeExpired'
    } finally { & $ops.Cleanup }
}
function Run-Start {
    $script:Station=Get-Station -RequireProfile:(!$Capture)
    $script:NativePath=$script:Station.NativePath;$script:YmPath=Join-Path (Split-Path $script:NativePath) 'YmLAN.exe'
    $script:Tag='bridge'+[Guid]::NewGuid().ToString('N')
    $stateDir=Join-Path $script:Root 'launcher-state';Assert-DataPath $stateDir
    New-Item -ItemType Directory -Path $stateDir -Force|Out-Null
    $script:Manifest=Join-Path $stateDir 'owner.json'
    # OS file lock prevents two starting owners, including the pre-manifest window.
    $lock=[IO.File]::Open((Join-Path $stateDir 'owner.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    try{
        Assert-NoAdapter
        if(Test-Path -LiteralPath $script:Manifest){throw 'ExistingOwnerRequiresInspection'}
        if((Get-Process -Id $PID).SessionId -eq 0){throw 'InteractiveDesktopRequired'}
        foreach($name in @('voice-adapter.ps1','observe-room-extended.ps1','capture-startup-adapter.ps1','BridgeProtocol.dll','BridgeConfigCore.dll')){
            if(!(Test-Path -LiteralPath (Join-Path $script:Bin $name) -PathType Leaf)){throw 'MissingDependency'}
        }
        if((Get-FileHash -LiteralPath $script:NativePath).Hash -cne $script:NativeHash){throw 'NativeHashMismatch'}
        Assert-Binary 'BridgeProtocol.dll';Assert-Binary 'BridgeConfigCore.dll'
        New-DiscoveryBackup $script:Station
        $aliases=Load-Aliases
        $script:Owner=@{Version=1;Root=$script:Root;Tag=$script:Tag;Supervisor=(Identity (Get-Process -Id $PID));Adapter=$null;Observer=$null;Native=$null;Aliases=$aliases;State='Starting'}
        $script:Owner.RuntimeMode=if($UntilStopped){'UntilOperatorStop'}else{'Bounded'}
        $runtimeArgs=if($UntilStopped){' -UntilStopped'}else{''}
        Save-Owner
        $script:Log=Join-Path $stateDir ($script:Tag+'.stdout')
        $ops=@{
            Preflight={Assert-NoAdapter}
            Prepare={
                # Only explicit -Start reaches here. No service or startup settings touched.
                foreach($p in @(Exact-Processes 'YmLAN' $script:YmPath)){Close-Exact $p $true}
                foreach($p in @(Exact-Processes 'Wires-X' $script:NativePath)){Close-Exact $p $false}
                Assert-NoAdapter
                Apply-Aliases
            }
            Adapter={
                Assert-NoAdapter
                $p=if($Capture){Spawn-Script 'capture-startup-adapter.ps1' ('-Seconds 120 -Tag '+$script:Tag) $script:Log}else{Spawn-Script 'voice-adapter.ps1' ('-Seconds 18000 -Tag '+$script:Tag+' -ForwardVoice -AssemblyName BridgeProtocol.dll'+$runtimeArgs) $script:Log}
                $script:Owner.Adapter=Identity $p;Save-Owner
            }
            Alive={ $null -ne (Matching $script:Owner.Adapter) }
            Ready={
                # Bounded metadata-only read. Never parse result/voice/private files.
                if(!(Test-Path -LiteralPath $script:Log)){return $false}
                $f=[IO.File]::Open($script:Log,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite)
                try{
                    if($f.Length -gt 65536){throw 'UnexpectedAdapterOutputSize'}
                    $r=New-Object IO.StreamReader($f)
                    try{$text=$r.ReadToEnd();if($Capture){return $text -cmatch '(?m)^ADAPTER_READY;VOICE=False;PHYSICAL_TRANSMIT=False;SAVED_CONFIG_ONLY=True\r?$'};return $text -cmatch '(?m)^ADAPTER_READY;EXPERIMENTAL_VOICE=True;PHYSICAL_TRANSMIT=False;ROOM_GATE=CURRENT_NATIVE_CONNECTION\r?$'}finally{$r.Dispose()}
                }finally{$f.Dispose()}
            }
            Native={
                if(Get-Process -Name Wires-X -ErrorAction SilentlyContinue){throw 'ForeignNativeAppeared'}
                $p=Start-Process -FilePath $script:NativePath -WorkingDirectory (Split-Path $script:NativePath) -PassThru
                $script:Owner.Native=Identity $p;Save-Owner
            }
            Observer={
                if($Capture){return}
                $p=Matching $script:Owner.Native
                if(!$p){throw 'NativeExited'}
                $argsLine='-Tag '+$script:Tag+' -Seconds 18060 -AppPid '+$p.Id+' -StartUtc "'+$script:Owner.Native.Created+'"'
                $argsLine+=$runtimeArgs
                $q=Spawn-Script 'observe-room-extended.ps1' $argsLine
                $script:Owner.Observer=Identity $q;$script:Owner.State='Running';Save-Owner
                Emit 'Running' @{Tag=$script:Tag;Settings='AppliedAtAdapterStartOnly';RuntimeMode=$script:Owner.RuntimeMode;RuntimeSeconds=$(if($UntilStopped){$null}else{18000})}
            }
            Healthy={ ($null -ne (Matching $script:Owner.Native)) -and ($Capture -or ($null -ne (Matching $script:Owner.Observer))) }
            Stop={Test-Path -LiteralPath (Join-Path $script:Root ('stop-'+$script:Tag+'.flag'))}
            Tick={Start-Sleep -Milliseconds 250}
            Cleanup={Cleanup-Real}
        }
        $reason=Invoke-Lifecycle $ops -untilStopped ([bool]$UntilStopped)
        if($Capture -and $reason -ceq 'CaptureComplete'){
            $result=Get-Content (Join-Path $script:Root ('adapter-'+$script:Tag+'-result.json')) -Raw|ConvertFrom-Json
            if($result.Error -or !$result.PortsReleased){throw 'CaptureFailed'}
            Import-OwnProfile (Join-Path $script:Root ('private-baseline\startup-'+$script:Tag+'.json'))
            Emit 'ProfileCaptured' @{Private=$true;VoiceRecorded=$false}
        }
        Emit 'Stopped' @{Reason=$reason;Tag=$script:Tag}
    }finally{$lock.Dispose()}
}
try{
    if(@($Capture,$Start,$Stop,$Recover,$CheckOnly,$SelfTest|Where-Object {$_}).Count -ne 1){throw 'ChooseExactlyOneAction'}
    if($SelfTest){throw 'RunSourceTestsSeparately'}
    if($CheckOnly){
        $setupReady=$false;try{$station=Get-Station -RequireProfile;if((Get-FileHash -LiteralPath $station.NativePath).Hash -ceq $script:NativeHash){$setupReady=$true}}catch{}
        $a=@(Find-BridgeAdapters)
        Emit 'Check' @{Root=$script:Root;ExistingBridge=($a.Count -gt 0);AdapterPids=@($a|ForEach-Object {$_.ProcessId});OwnerManifestPresent=(Test-Path -LiteralPath (Join-Path $script:Root 'launcher-state\owner.json'));NonInvasive=$true;SetupReady=$setupReady}
    }elseif($Recover){
        Emit 'Recovered' (Invoke-InterruptedBridgeRecovery)
    }elseif($Stop){
        $m=Get-Content -LiteralPath (Join-Path $script:Root 'launcher-state\owner.json') -Raw|ConvertFrom-Json
        if($m.Root -cne $script:Root -or $m.Tag -cnotmatch '^bridge[a-f0-9]{32}$' -or $m.Supervisor.Tag -cne $m.Tag){throw 'InvalidOwner'}
        $script:Tag=$m.Tag
        if(!(Matching $m.Supervisor)){throw 'SupervisorNotAliveManualRecoveryRequired'}
        Owned-Flag 'stop-'
        if(!(Test-Path -LiteralPath (Join-Path $script:Root ('stop-'+$script:Tag+'.flag')))){throw 'StopVerificationFailed'}
        Emit 'StopRequested' @{Tag=$script:Tag;Completed=$false}
    }else{Run-Start}
}catch{
    # Fixed error code/type only: do not echo command lines, endpoints or private data.
    $failure=@{Code=($_.Exception.Message -replace '[^A-Za-z0-9,]','');Type=$_.Exception.GetType().Name;Pid=$PID;Utc=[DateTime]::UtcNow.ToString('o')}
    try{$errorPath=Join-Path $script:Root 'last-controller-error.json';Assert-DataPath $errorPath;$pending=$errorPath+'.'+$PID+'.pending';Assert-DataPath $pending;$failure|ConvertTo-Json|Set-Content -LiteralPath $pending -Encoding UTF8;Move-Item -LiteralPath $pending -Destination $errorPath -Force}catch{}
    Emit 'Error' $failure
    exit 1
}
