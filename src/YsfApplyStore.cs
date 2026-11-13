// Copyright (c) 2026 M5LEE. MIT; see LICENSE.
using System;
using System.IO;
using System.Text;
using System.Diagnostics;
using System.Globalization;
using System.Text.RegularExpressions;
using System.Collections.Generic;
using System.Web.Script.Serialization;
namespace CumbriaCQ.Configuration {
 public sealed class YsfApplyRequest {public string RequestId {get;set;} public BridgeSettings Settings {get;set;}}
 public sealed class YsfApplyView {public string ActiveLabel {get;set;} public string RequestId {get;set;} public string State {get;set;} public string Message {get;set;} public string ErrorRequestId {get;set;} public string Error {get;set;} public bool Pending {get;set;}}
 public static class YsfApplyStore {
  static string Safe(string path){
   path=Path.GetFullPath(path);string cursor=path;while(!String.IsNullOrEmpty(cursor)){if((File.Exists(cursor)||Directory.Exists(cursor)) && (File.GetAttributes(cursor)&FileAttributes.ReparsePoint)!=0)throw new IOException("Linked live-control paths are not supported");cursor=Path.GetDirectoryName(cursor);}return path;
  }
  static Dictionary<string,object> Read(string path){
   path=Safe(path);using(var f=new FileStream(path,FileMode.Open,FileAccess.Read,FileShare.ReadWrite|FileShare.Delete)){
    if(f.Length>1048576)throw new IOException("Live-control file is too large");
    using(var reader=new StreamReader(f,new UTF8Encoding(false,true),true)){var value=new JavaScriptSerializer{MaxJsonLength=1048576,RecursionLimit=16}.DeserializeObject(reader.ReadToEnd()) as Dictionary<string,object>;if(value==null)throw new ArgumentException("Expected live-control object");return value;}
   }
  }
  static string Text(Dictionary<string,object> d,string key){object v;if(!d.TryGetValue(key,out v)||!(v is string))throw new ArgumentException("Invalid live-control field: "+key);return (string)v;}
  static int Number(Dictionary<string,object> d,string key){object v;if(!d.TryGetValue(key,out v)||!(v is int))throw new ArgumentException("Invalid live-control number: "+key);return (int)v;}
  static void Tag(string tag){if(!Regex.IsMatch(tag??"",@"\Abridge[a-f0-9]{32}\z"))throw new ArgumentException("Invalid bridge owner tag");}
  static void Publish(string path,object value){
   path=Safe(path);string temp=Safe(path+"."+Guid.NewGuid().ToString("N")+".pending");
   try{File.WriteAllText(temp,new JavaScriptSerializer().Serialize(value),new UTF8Encoding(false));if(File.Exists(path))File.Replace(temp,path,null);else File.Move(temp,path);}finally{if(File.Exists(temp))File.Delete(temp);}
  }
  static Dictionary<string,object> Progress(string root,string bin,out string tag,out int pid,out string created){
   root=Safe(root).TrimEnd(Path.DirectorySeparatorChar);bin=Safe(bin).TrimEnd(Path.DirectorySeparatorChar);
   var owner=Read(Path.Combine(root,"launcher-state","owner.json"));tag=Text(owner,"Tag");Tag(tag);
   if(Text(owner,"Root")!=root || Text(owner,"State")!="Running")throw new InvalidOperationException("No running bridge owned by this station");
   object raw;var adapter=owner.TryGetValue("Adapter",out raw)?raw as Dictionary<string,object>:null;if(adapter==null || Text(adapter,"Root")!=root || Text(adapter,"Tag")!=tag)throw new InvalidOperationException("Unverified adapter ownership");
   pid=Number(adapter,"Pid");created=Text(adapter,"Created");using(var process=Process.GetProcessById(pid)){if(process.StartTime.ToUniversalTime().ToString("o")!=created)throw new InvalidOperationException("The adapter process has changed");}
   string progressPath=Path.Combine(root,"progress-"+tag+".json");var progress=Read(progressPath);double age=(DateTime.UtcNow-File.GetLastWriteTimeUtc(progressPath)).TotalSeconds;
   object version;if(!progress.TryGetValue("YsfApplyVersion",out version)||!Object.Equals(version,1))throw new InvalidOperationException("This running bridge needs one initial restart to enable live YSF apply. WIRES-X was not restarted.");
   if(age< -2 || age>10 || Text(progress,"Tag")!=tag || Number(progress,"AdapterPid")!=pid || Text(progress,"AdapterStartUtc")!=created || Text(progress,"YsfProgramRoot")!=bin)throw new InvalidOperationException("The running bridge could not be freshly verified");
   return progress;
  }
  public static string Submit(string root,string bin){
   string tag,created;int pid;Progress(root,bin,out tag,out pid,out created);
   var settings=SettingsStore.Open(Path.Combine(root,"bridge-config.json"));if(settings.Fingerprint=="MISSING")throw new InvalidOperationException("Save the YSF settings first");
   string id=Guid.NewGuid().ToString("N");Publish(Path.Combine(root,"ysf-apply-"+tag+".json"),new {SchemaVersion=1,RequestId=id,Tag=tag,AdapterPid=pid,AdapterStartUtc=created,ConfigFingerprint=settings.Fingerprint,RequestedUtc=DateTime.UtcNow.ToString("o")});return id;
  }
  public static YsfApplyView View(string root,string bin){
   string tag,created;int pid;var progress=Progress(root,bin,out tag,out pid,out created);object raw;
   var active=progress.TryGetValue("YsfActive",out raw)?raw as Dictionary<string,object>:null;
   if(active==null)throw new InvalidOperationException("No verified active YSF destination");
   var view=new YsfApplyView{ActiveLabel=Text(active,"YsfRoomId")+" "+Text(active,"YsfRoomName"),RequestId="",State="Idle",Message="",ErrorRequestId="",Error=""};
   var apply=progress.TryGetValue("YsfApply",out raw)?raw as Dictionary<string,object>:null;
   if(apply!=null){if(apply.ContainsKey("RequestId"))view.RequestId=Text(apply,"RequestId");if(apply.ContainsKey("State"))view.State=Text(apply,"State");if(apply.ContainsKey("Message"))view.Message=Text(apply,"Message");if(apply.ContainsKey("ErrorRequestId"))view.ErrorRequestId=Text(apply,"ErrorRequestId");if(apply.ContainsKey("Error"))view.Error=Text(apply,"Error");view.Pending=apply.TryGetValue("Pending",out raw)&&Object.Equals(raw,true);}
   return view;
  }
  public static YsfApplyRequest ReadForAdapter(string root,string tag,int pid,string created,string lastId){
   Tag(tag);root=Safe(root);string path=Safe(Path.Combine(root,"ysf-apply-"+tag+".json"));if(!File.Exists(path))return null;var request=Read(path);string id=Text(request,"RequestId");
   if(!Regex.IsMatch(id,@"\A[a-f0-9]{32}\z"))throw new ArgumentException("Invalid apply request ID");if(id==lastId)return null;
   if(Number(request,"SchemaVersion")!=1 || Text(request,"Tag")!=tag || Number(request,"AdapterPid")!=pid || Text(request,"AdapterStartUtc")!=created)throw new InvalidOperationException("Stale YSF apply owner");
   DateTime utc=DateTime.Parse(Text(request,"RequestedUtc"),CultureInfo.InvariantCulture,DateTimeStyles.RoundtripKind).ToUniversalTime();double age=(DateTime.UtcNow-utc).TotalSeconds;if(age< -5 || age>300)throw new InvalidOperationException("YSF apply request expired");
   var settings=SettingsStore.Open(Path.Combine(root,"bridge-config.json"));if(settings.Fingerprint!=Text(request,"ConfigFingerprint"))throw new InvalidOperationException("Saved settings changed; apply the room again");return new YsfApplyRequest{RequestId=id,Settings=settings.Settings};
  }
 }
}
