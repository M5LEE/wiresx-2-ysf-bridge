using System;
using System.IO;
using System.Text;
using System.Text.RegularExpressions;
using System.Collections.Generic;
using System.Security.Cryptography;
using System.Web.Script.Serialization;
using System.Globalization;
using CumbriaCQ.Catalog;
namespace CumbriaCQ.Configuration {
 public sealed class BridgeSettings {
  public int SchemaVersion {get;set;}
  public string YsfRoomId {get;set;} public string YsfRoomName {get;set;}
  public string YsfHost {get;set;} public int YsfPort {get;set;}
  public int DgId {get;set;} public bool AllowZeroDg {get;set;}
 }
 public sealed class ConfigSession {public BridgeSettings Settings {get;set;} public string Fingerprint {get;set;}}
 public sealed class CatalogSnapshot {public System.Collections.Generic.List<Room> Rooms {get;set;} public DateTime FetchedAtUtc {get;set;}}
 public static class CatalogView {
  public static CatalogSnapshot Load(string path){
   byte[] bytes;using(var f=new FileStream(path,FileMode.Open,FileAccess.Read,FileShare.Read))bytes=CumbriaCQ.Catalog.Catalog.ReadBounded(f,3000000);
   string json;using(var r=new StreamReader(new MemoryStream(bytes),new UTF8Encoding(false,true),true))json=r.ReadToEnd();
   var serializer=new JavaScriptSerializer {MaxJsonLength=3000000,RecursionLimit=32};var d=serializer.DeserializeObject(json) as Dictionary<string,object>;
   if(d==null || !d.ContainsKey("SchemaVersion") || !(d["SchemaVersion"] is int) || (int)d["SchemaVersion"]!=1 || !d.ContainsKey("SourceUrl") || !Object.Equals(d["SourceUrl"],CumbriaCQ.Catalog.Catalog.SourceUrl) || !d.ContainsKey("Count") || !(d["Count"] is int) || !d.ContainsKey("Rooms"))throw new ArgumentException("Unknown catalogue cache format");
   var rows=d["Rooms"] as object[];if(rows==null || rows.Length==0 || rows.Length>20000 || (int)d["Count"]!=rows.Length)throw new ArgumentException("Invalid catalogue count");
   object fetched;DateTimeOffset timestamp;if(!d.TryGetValue("FetchedAtUtc",out fetched) || !(fetched is string) || !DateTimeOffset.TryParse((string)fetched,CultureInfo.InvariantCulture,DateTimeStyles.AssumeUniversal,out timestamp) || timestamp.UtcDateTime>DateTime.UtcNow.AddMinutes(5))throw new ArgumentException("Invalid catalogue timestamp");
   var source=new List<Dictionary<string,object>>();
   foreach(object item in rows){
    var row=item as Dictionary<string,object>;if(row==null || !row.ContainsKey("Id") || !row.ContainsKey("Name") || !row.ContainsKey("Host") || !row.ContainsKey("Port"))throw new ArgumentException("Invalid cached room");
    source.Add(new Dictionary<string,object>{{"designator",row["Id"]},{"name",row["Name"]},{"description",row.ContainsKey("Description")?row["Description"]:""},{"dns",row["Host"]},{"port",row["Port"]},{"country",row.ContainsKey("Country")?row["Country"]:""}});
   }
   var rooms=CumbriaCQ.Catalog.Catalog.Parse(serializer.Serialize(new {reflectors=source}));if(rooms.Count!=rows.Length)throw new ArgumentException("Duplicate catalogue IDs");
   return new CatalogSnapshot {Rooms=rooms,FetchedAtUtc=timestamp.UtcDateTime};
  }
  public static List<Room> Filter(List<Room> rooms,string query){
   if(rooms==null)throw new ArgumentNullException("rooms");query=(query??"").Trim();var found=new List<Room>();
   foreach(var room in rooms)if((room.Id+" "+room.Name+" "+room.Description+" "+room.Host+" "+room.Country).IndexOf(query,StringComparison.OrdinalIgnoreCase)>=0)found.Add(room);
   return found;
  }
 }
 public static class SettingsStore {
  public static BridgeSettings Defaults(){return new BridgeSettings {SchemaVersion=1,YsfRoomId="23534",YsfRoomName="CUMBRIACQ",YsfHost="57.128.190.202",YsfPort=42100,DgId=50,AllowZeroDg=true};}
  static JavaScriptSerializer Serializer(){return new JavaScriptSerializer {MaxJsonLength=65536,RecursionLimit=16};}
  static string SafePath(string path){
   path=Path.GetFullPath(path);string cursor=path;
   while(!String.IsNullOrEmpty(cursor)){
    if((File.Exists(cursor) || Directory.Exists(cursor)) && (File.GetAttributes(cursor)&FileAttributes.ReparsePoint)!=0)throw new IOException("Linked configuration paths are not supported");
    cursor=Path.GetDirectoryName(cursor);
   }
   return path;
  }
  static byte[] Bytes(string path){using(var f=new FileStream(path,FileMode.Open,FileAccess.Read,FileShare.Read))return CumbriaCQ.Catalog.Catalog.ReadBounded(f,65536);}
  static string Hash(byte[] bytes){using(var h=SHA256.Create())return BitConverter.ToString(h.ComputeHash(bytes)).Replace("-","");}
  static Dictionary<string,object> Raw(byte[] bytes){
   string json;using(var r=new StreamReader(new MemoryStream(bytes),new UTF8Encoding(false,true),true))json=r.ReadToEnd();
   var d=Serializer().DeserializeObject(json) as Dictionary<string,object>;if(d==null)throw new ArgumentException("Expected a configuration object");return d;
  }
  static int Number(Dictionary<string,object> d,string key){object v;if(!d.TryGetValue(key,out v) || !(v is int))throw new ArgumentException("Invalid numeric field: "+key);return (int)v;}
  static string Text(Dictionary<string,object> d,string key){object v;if(!d.TryGetValue(key,out v) || !(v is string))throw new ArgumentException("Invalid text field: "+key);return (string)v;}
  static BridgeSettings Decode(Dictionary<string,object> d){
   object zero;if(!d.TryGetValue("AllowZeroDg",out zero) || !(zero is bool))throw new ArgumentException("Invalid DG-ID policy");
   var s=new BridgeSettings {SchemaVersion=Number(d,"SchemaVersion"),YsfRoomId=Text(d,"YsfRoomId"),YsfRoomName=Text(d,"YsfRoomName"),YsfHost=Text(d,"YsfHost"),YsfPort=Number(d,"YsfPort"),DgId=Number(d,"DgId"),AllowZeroDg=(bool)zero};Validate(s);return s;
  }
  public static void Validate(BridgeSettings s){
   if(s==null || s.SchemaVersion!=1 || !Regex.IsMatch(s.YsfRoomId??"",@"\A[0-9]{5}\z"))throw new ArgumentException("Expected schema 1 and an exact five-digit YSF ID");
   if(String.IsNullOrEmpty(s.YsfRoomName) || s.YsfRoomName.Length>256)throw new ArgumentException("Invalid reflector name");
   foreach(char c in s.YsfRoomName)if(Char.IsControl(c))throw new ArgumentException("Control in reflector name");
   if(String.IsNullOrEmpty(s.YsfHost) || s.YsfHost.Length>253 || s.YsfHost.Trim()!=s.YsfHost || Uri.CheckHostName(s.YsfHost)==UriHostNameType.Unknown)throw new ArgumentException("Invalid reflector host");
   if(s.YsfPort<1 || s.YsfPort>65535 || s.DgId<0 || s.DgId>127)throw new ArgumentException("Invalid UDP port or DG-ID");
  }
  public static ConfigSession Open(string path){
   path=SafePath(path);if(!File.Exists(path))return new ConfigSession {Settings=Defaults(),Fingerprint="MISSING"};
   byte[] b=Bytes(path);return new ConfigSession {Settings=Decode(Raw(b)),Fingerprint=Hash(b)};
  }
  public static string Save(string path,BridgeSettings settings,string expectedFingerprint){
   Validate(settings);path=SafePath(path);Directory.CreateDirectory(Path.GetDirectoryName(path));SafePath(path+".lock");
   using(var guard=new FileStream(path+".lock",FileMode.OpenOrCreate,FileAccess.ReadWrite,FileShare.None)){
    byte[] previous=File.Exists(path)?Bytes(path):null;string actual=previous==null?"MISSING":Hash(previous);
    if(actual!=expectedFingerprint)throw new IOException("Configuration changed. Reload before saving.");
    var d=previous==null?new Dictionary<string,object>():Raw(previous);if(previous!=null)Decode(d);
    d["SchemaVersion"]=settings.SchemaVersion;d["YsfRoomId"]=settings.YsfRoomId;d["YsfRoomName"]=settings.YsfRoomName;d["YsfHost"]=settings.YsfHost;d["YsfPort"]=settings.YsfPort;d["DgId"]=settings.DgId;d["AllowZeroDg"]=settings.AllowZeroDg;
    byte[] body=new UTF8Encoding(false).GetBytes(Serializer().Serialize(d));if(body.Length>65536)throw new ArgumentException("Configuration too large");
    string pending=path+"."+Guid.NewGuid().ToString("N")+".pending";string backup=previous==null?"":path+".backup-"+DateTime.UtcNow.ToString("yyyyMMddTHHmmssfffffffZ")+"-"+Guid.NewGuid().ToString("N");
    try{
     using(var f=new FileStream(pending,FileMode.CreateNew,FileAccess.Write,FileShare.None,4096,FileOptions.WriteThrough)){f.Write(body,0,body.Length);f.Flush(true);}
     if(previous==null)File.Move(pending,path);else File.Replace(pending,path,backup);
    }finally{if(File.Exists(pending))File.Delete(pending);}
    if(Hash(Bytes(path))!=Hash(body))throw new IOException("Saved configuration verification failed");return backup;
   }
  }
 }
}
