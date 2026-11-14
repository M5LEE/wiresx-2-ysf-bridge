param([Parameter(Mandatory=$true)][string]$ObserverPath,[Parameter(Mandatory=$true)][string]$AssemblyPath)
$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
[Reflection.Assembly]::LoadFrom($AssemblyPath)|Out-Null
$source=[IO.File]::ReadAllText($ObserverPath);$from=$source.IndexOf(' $path=Join-Path');$to=$source.IndexOf(' # A temporary read failure',$from)
if($from -lt 0 -or $to -le $from){throw 'ActualProofPublicationBlockNotFound'}
$block=[ScriptBlock]::Create($source.Substring($from,$to-$from))
Add-Type -TypeDefinition @'
using System;using System.IO;using System.Threading;using System.Reflection;
public sealed class ProofFileReader {
 volatile bool stop;Thread thread;public int Reads,Failures,Malformed,Missing,Access,Other,Busy;public string OtherReason;readonly string path;readonly Func<string,string> read;
 public ProofFileReader(string p,string assembly){path=p;Type type=Assembly.LoadFrom(assembly).GetType("CumbriaCQ.Offline.RoomProofFile");if(type!=null)read=(Func<string,string>)Delegate.CreateDelegate(typeof(Func<string,string>),type.GetMethod("Read"));else read=RawRead;}
 static string RawRead(string p){using(var f=new FileStream(p,FileMode.Open,FileAccess.Read,FileShare.ReadWrite|FileShare.Delete))using(var r=new StreamReader(f))return r.ReadToEnd();}
 public void Start(){thread=new Thread(Run);thread.IsBackground=true;thread.Start();}
 void Run(){while(!stop){try{string text=read(path).Trim();if(!text.StartsWith("{")||!text.EndsWith("}")||!text.Contains("\"Sequence\""))Malformed++;Reads++;}catch(FileNotFoundException){Failures++;Missing++;}catch(IOException e){Failures++;if(e.Message=="RoomProofBusy")Busy++;else{Other++;OtherReason=e.GetType().Name+":"+e.HResult;}}catch(UnauthorizedAccessException){Failures++;Access++;}Thread.Yield();}}
 public void Stop(){stop=true;if(!thread.Join(5000))throw new Exception("ReaderStopTimeout");}
 public bool ProveBoundedContention(string assembly){
  Type type=Assembly.LoadFrom(assembly).GetType("CumbriaCQ.Offline.RoomProofFile");if(type==null)return false;
  using(var gate=(Mutex)type.GetMethod("OpenLock",BindingFlags.NonPublic|BindingFlags.Static).Invoke(null,new object[]{path})){
   gate.WaitOne();bool refused=false,finished=false;
   try{var blocked=new Thread(delegate(){try{read(path);}catch(IOException e){refused=e.Message=="RoomProofBusy";}});blocked.IsBackground=true;blocked.Start();finished=blocked.Join(1000);}finally{gate.ReleaseMutex();}
   return finished && refused && read(path).Contains("\"Sequence\"");
  }
 }
}
'@
$root=Join-Path (Split-Path $ObserverPath) ('proof-publication-'+[Guid]::NewGuid().ToString('N'));[IO.Directory]::CreateDirectory($root)|Out-Null;$Tag='testproof'
$path=Join-Path $root ('room-proof-'+$Tag+'.json');[IO.File]::WriteAllText($path,'{"Sequence":0}');$reader=[ProofFileReader]::new($path,$AssemblyPath)
try{
 $reader.Start()
 for($n=1;$n -le 1000;$n++){$state=[pscustomobject]@{Sequence=$n;Connected=$true;Utc=[DateTime]::UtcNow.ToString('o')};. $block}
 $reader.Stop();$last=Get-Content $path -Raw|ConvertFrom-Json
 Write-Output ('PROOF_PUBLICATION reads='+$reader.Reads+' failures='+$reader.Failures+' missing='+$reader.Missing+' access='+$reader.Access+' other='+$reader.Other+' otherReason='+$reader.OtherReason+' boundedBusy='+$reader.Busy+' malformed='+$reader.Malformed+' final='+$last.Sequence)
 # Saturated contention may refuse a read within its finite budget; it must not
 # return missing/partial data or reuse stale proof to manufacture success.
 if($reader.Reads -lt 100 -or $reader.Failures -ne $reader.Busy -or $reader.Malformed -ne 0 -or $last.Sequence -ne 1000){throw 'Publication must never expose a missing or partial proof'}
 if(!$reader.ProveBoundedContention($AssemblyPath)){throw 'Contended proof reads must fail closed within a bounded wait and recover after release'}
 Write-Output 'PROOF_PUBLICATION_PASS actual_writer=true shared_reader=true'
}finally{$reader.Stop();Remove-Item $root -Recurse -Force}
