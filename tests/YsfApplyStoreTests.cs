using System;
using System.IO;
using System.Diagnostics;
using System.Reflection;
using System.Collections.Generic;
using System.Web.Script.Serialization;
using CumbriaCQ.Configuration;
static class YsfApplyStoreTests {
 static int checks;static Type store;static string root,bin;static JavaScriptSerializer json=new JavaScriptSerializer();
 static void Check(bool ok,string why){if(!ok)throw new Exception(why);checks++;}
 static object Call(string method,params object[] args){return store.GetMethod(method).Invoke(null,args);}
 static void Put(string path,object value){Directory.CreateDirectory(Path.GetDirectoryName(path));File.WriteAllText(path,json.Serialize(value));}
 static int Main(string[] args){try{
  store=typeof(BridgeSettings).Assembly.GetType("CumbriaCQ.Configuration.YsfApplyStore");Check(store!=null,"Apply YSF room must queue an owner-bound request for the running adapter");root=Path.GetFullPath(args[0]);bin=Path.Combine(root,"bin");Directory.CreateDirectory(bin);
  var process=Process.GetCurrentProcess();string start=process.StartTime.ToUniversalTime().ToString("o"),tag="bridge"+new string('a',32);
  var identity=new {Pid=process.Id,Created=start,Root=root,Tag=tag};Put(Path.Combine(root,"launcher-state","owner.json"),new {Root=root,Tag=tag,State="Running",Adapter=identity});
  Put(Path.Combine(root,"progress-"+tag+".json"),new {Tag=tag,AdapterPid=process.Id,AdapterStartUtc=start,YsfApplyVersion=1,YsfProgramRoot=bin,YsfActive=SettingsStore.Defaults()});
  var config=SettingsStore.Defaults();config.YsfRoomId="00016";config.YsfRoomName="TEST NEW ROOM";SettingsStore.Save(Path.Combine(root,"bridge-config.json"),config,"MISSING");
  string id=(string)Call("Submit",root,bin);Check(id.Length==32,"Apply must have a unique request ID");
  object request=Call("ReadForAdapter",root,tag,process.Id,start,"");Check(request!=null,"The exact running adapter must be able to read the queued request");var rt=request.GetType();Check((string)rt.GetProperty("RequestId").GetValue(request,null)==id,"Request ID must survive the queue");Check(((BridgeSettings)rt.GetProperty("Settings").GetValue(request,null)).YsfRoomId=="00016","Requested target must match the saved fingerprint");Check(Call("ReadForAdapter",root,tag,process.Id,start,id)==null,"A consumed request must not repeat");
  bool wrong=false;try{Call("ReadForAdapter",root,tag,process.Id,start+"x","");}catch(TargetInvocationException){wrong=true;}Check(wrong,"A stale process-start identity must be rejected");
  string queued=File.ReadAllText(Path.Combine(root,"ysf-apply-"+tag+".json"));
  config.YsfRoomName="CHANGED AFTER CLICK";SettingsStore.Save(Path.Combine(root,"bridge-config.json"),config,SettingsStore.Open(Path.Combine(root,"bridge-config.json")).Fingerprint);bool drift=false;try{Call("ReadForAdapter",root,tag,process.Id,start,"");}catch(TargetInvocationException ex){drift=ex.InnerException is InvalidOperationException;}Check(drift,"A changed saved fingerprint must not silently switch to a different selection");
  Put(Path.Combine(root,"progress-"+tag+".json"),new {Tag=tag,AdapterPid=process.Id,AdapterStartUtc=start,YsfProgramRoot=bin});bool old=false;try{Call("Submit",root,bin);}catch(TargetInvocationException ex){old=ex.InnerException.Message.Contains("initial restart");}Check(old,"An old running adapter must explicitly report its missing capability");Check(File.ReadAllText(Path.Combine(root,"ysf-apply-"+tag+".json"))==queued,"A rejected apply must not alter an existing request or restart a process");
  Put(Path.Combine(root,"progress-"+tag+".json"),new {Tag=tag,AdapterPid=process.Id,AdapterStartUtc=start,YsfApplyVersion=1,YsfProgramRoot=bin});File.SetLastWriteTimeUtc(Path.Combine(root,"progress-"+tag+".json"),DateTime.UtcNow.AddSeconds(-30));bool stale=false;try{Call("Submit",root,bin);}catch(TargetInvocationException){stale=true;}Check(stale,"Stale live status must refuse a new control request");
  File.SetLastWriteTimeUtc(Path.Combine(root,"progress-"+tag+".json"),DateTime.UtcNow);bool foreign=false;try{Call("Submit",root,Path.Combine(bin,"other"));}catch(TargetInvocationException){foreign=true;}Check(foreign,"Another installed-program root must not control the running adapter");
  Console.WriteLine("YSF_APPLY_STORE_PASS checks="+checks+" native_touched=false");return 0;
 }catch(Exception ex){Console.WriteLine(ex.ToString());return 1;}}
}
