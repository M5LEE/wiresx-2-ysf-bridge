using System;
using System.IO;
using System.Reflection;
using System.Diagnostics;
using System.Web.Script.Serialization;
class StatusWorkerTests {
 static int checks;
 static void Check(bool ok,string why){if(!ok)throw new Exception(why);checks++;}
 static bool Alive(int id){try{using(var p=Process.GetProcessById(id))return !p.HasExited;}catch(ArgumentException){return false;}}
 static object Read(object worker){return worker.GetType().GetMethod("Read").Invoke(worker,null);}
 static int Pid(object reply){return Convert.ToInt32(((System.Collections.Generic.Dictionary<string,object>)new JavaScriptSerializer().DeserializeObject(Convert.ToString(reply)))["Pid"]);}
 static int Main(string[] args){string fixture=Path.Combine(args[1],"status-worker-"+Guid.NewGuid().ToString("N"));Directory.CreateDirectory(fixture);object worker=null;
  try{
   var type=Assembly.LoadFrom(Path.Combine(args[0],"Bridge.exe")).GetType("BridgeStatusWorker");Check(type!=null,"Status polling must reuse an owned helper instead of spawning PowerShell on every refresh");
   File.WriteAllText(Path.Combine(fixture,"mode.txt"),"normal");
   File.WriteAllText(Path.Combine(fixture,"BridgeStatus.ps1"),"param([switch]$Watch)\n$ErrorActionPreference='Stop';[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false);$n=0;[IO.File]::WriteAllText((Join-Path $PSScriptRoot 'pid.txt'),[string]$PID);while(($line=[Console]::ReadLine()) -ne $null){if($line -cne 'CHECK'){throw 'BadCommand'};$mode=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'mode.txt'));if($mode -eq 'exit'){exit 42};if($mode -eq 'hang'){Start-Sleep 60};$n++;[Console]::WriteLine((@{Pid=$PID;N=$n;Watch=[bool]$Watch}|ConvertTo-Json -Compress))}\n");
   worker=Activator.CreateInstance(type,BindingFlags.Instance|BindingFlags.Public|BindingFlags.NonPublic,null,new object[]{fixture,10000},null);
   int first=Pid(Read(worker)),second=Pid(Read(worker));Check(first==second,"Consecutive checks must reuse the same process");
   var response=(System.Collections.Generic.Dictionary<string,object>)new JavaScriptSerializer().DeserializeObject(Convert.ToString(Read(worker)));Check(Convert.ToInt32(response["N"])==3 && Object.Equals(response["Watch"],true),"Each request must read fresh state via Watch, not cache a previous response");
   File.WriteAllText(Path.Combine(fixture,"mode.txt"),"exit");bool failed=false;try{Read(worker);}catch(TargetInvocationException){failed=true;}Check(failed,"An exited helper must fail closed");
   File.WriteAllText(Path.Combine(fixture,"mode.txt"),"normal");int restarted=Pid(Read(worker));Check(restarted!=first,"A later request must recover with a new owned helper");
   ((IDisposable)worker).Dispose();worker=null;Check(!Alive(restarted),"Disposing the status worker must release its child without stopping the bridge");
   worker=Activator.CreateInstance(type,BindingFlags.Instance|BindingFlags.Public|BindingFlags.NonPublic,null,new object[]{fixture,2500},null);File.WriteAllText(Path.Combine(fixture,"mode.txt"),"hang");failed=false;try{Read(worker);}catch(TargetInvocationException e){failed=e.InnerException is TimeoutException;}Check(failed,"Hung status requests must time out, not block indefinitely");int hung=int.Parse(File.ReadAllText(Path.Combine(fixture,"pid.txt")));Check(!Alive(hung),"Timeout must clean up only its owned helper");
   ((IDisposable)worker).Dispose();worker=null;Console.WriteLine("STATUS_WORKER_PASS checks="+checks);return 0;
  }catch(Exception e){Console.WriteLine(e.ToString());return 1;}finally{if(worker!=null)((IDisposable)worker).Dispose();Directory.Delete(fixture,true);}
 }
}
