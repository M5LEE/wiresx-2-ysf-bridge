// Copyright (c) 2026 M5LEE.
// SPDX-License-Identifier: GPL-3.0-or-later
using System;
using System.Collections.Generic;
using System.Web.Script.Serialization;
using System.Text.RegularExpressions;
using System.IO;
using System.Text;
using System.Security.Cryptography;
using System.Net;
using System.Diagnostics;
using System.Globalization;
namespace CumbriaCQ.Catalog {
 public sealed class Room {
  public string Id {get;set;} public string Name {get;set;} public string Description {get;set;}
  public string Host {get;set;} public int Port {get;set;} public string Country {get;set;}
 }
 public static class Catalog {
  public static byte[] ReadBounded(Stream input,int maximum){return ReadBounded(input,maximum,null);}
  static byte[] ReadBounded(Stream input,int maximum,Func<bool> expired){
   if(maximum<1)throw new ArgumentOutOfRangeException("maximum");
   using(var memory=new MemoryStream()){
    byte[] buffer=new byte[8192];int count;
    while(true){
     if(expired!=null && expired())throw new TimeoutException("Catalogue download time limit exceeded");
     count=input.Read(buffer,0,buffer.Length);if(count==0)break;
     if(memory.Length+count>maximum)throw new ArgumentException("Oversized catalogue download");
     memory.Write(buffer,0,count);
    }
    return memory.ToArray();
   }
  }
  public static int Refresh(string target){
   target=Path.GetFullPath(target);Directory.CreateDirectory(Path.GetDirectoryName(target));
   using(var guard=new FileStream(target+".refresh.lock",FileMode.OpenOrCreate,FileAccess.ReadWrite,FileShare.None)){
    ServicePointManager.SecurityProtocol=SecurityProtocolType.Tls12;
    var request=(HttpWebRequest)WebRequest.Create(SourceUrl);
    request.Method="GET";request.UserAgent="CumbriaCQ-RoomCatalog/0.1";request.Timeout=20000;request.ReadWriteTimeout=20000;request.AllowAutoRedirect=false;request.UseDefaultCredentials=false;
    var timer=Stopwatch.StartNew();
    using(var response=(HttpWebResponse)request.GetResponse()){
     if(response.StatusCode!=HttpStatusCode.OK || response.ResponseUri.AbsoluteUri!=SourceUrl)throw new ArgumentException("Unexpected source response or redirect");
     if(response.ContentLength>3000000)throw new ArgumentException("Oversized published source");
     string modified="";DateTimeOffset date;
     if(!String.IsNullOrEmpty(response.Headers["Last-Modified"])){
      if(!DateTimeOffset.TryParse(response.Headers["Last-Modified"],CultureInfo.InvariantCulture,DateTimeStyles.AssumeUniversal,out date))throw new ArgumentException("Malformed source timestamp");
      if(date.UtcDateTime<DateTime.UtcNow.AddDays(-7))throw new ArgumentException("Published source is older than seven days");
      modified=date.UtcDateTime.ToString("O");
     }
     using(var input=response.GetResponseStream()){
      byte[] bytes=ReadBounded(input,3000000,delegate{return timer.Elapsed.TotalSeconds>60;});
      using(var reader=new StreamReader(new MemoryStream(bytes),new UTF8Encoding(false,true),true))return Publish(reader.ReadToEnd(),target,100,modified);
     }
    }
   }
  }
  public const string SourceUrl="https://www.pistar.uk/downloads/YSFHosts.json";
  public static int Publish(string json,string target,int minimum,string lastModified){
   var rooms=Parse(json);if(minimum<1 || rooms.Count<minimum)throw new ArgumentException("Implausibly short registry; last good cache retained");
   var serializer=new JavaScriptSerializer {MaxJsonLength=3000000,RecursionLimit=32};
   target=Path.GetFullPath(target);
   if(File.Exists(target)){
    var old=serializer.DeserializeObject(File.ReadAllText(target)) as Dictionary<string,object>;
    if(old==null || !old.ContainsKey("Count") || !(old["Count"] is int))throw new ArgumentException("Unknown existing cache schema; not replacing it");
    if(rooms.Count<(int)old["Count"]*0.8)throw new ArgumentException("Registry unexpectedly lost more than 20 percent; last good cache retained");
   }
   string hash;using(var sha=SHA256.Create()){hash=BitConverter.ToString(sha.ComputeHash(Encoding.UTF8.GetBytes(json))).Replace("-","");}
   string body=serializer.Serialize(new {SchemaVersion=1,SourceUrl=SourceUrl,SourceUtf8Sha256=hash,SourceLastModifiedUtc=lastModified,FetchedAtUtc=DateTime.UtcNow.ToString("O"),Count=rooms.Count,Rooms=rooms});
   Directory.CreateDirectory(Path.GetDirectoryName(target));string pending=target+"."+Guid.NewGuid().ToString("N")+".pending";
   try{
    byte[] bytes=new UTF8Encoding(false).GetBytes(body);
    using(var stream=new FileStream(pending,FileMode.CreateNew,FileAccess.Write,FileShare.None,8192,FileOptions.WriteThrough)){stream.Write(bytes,0,bytes.Length);stream.Flush(true);}
    if(File.Exists(target))File.Replace(pending,target,null);else File.Move(pending,target);
   }finally{if(File.Exists(pending))File.Delete(pending);}
   return rooms.Count;
  }
  static string Text(Dictionary<string,object> row,string key,int max,bool required){
   object raw;string value=row.TryGetValue(key,out raw)?raw as string:null;
   if(raw!=null && value==null)throw new ArgumentException("Unexpected field type: "+key);
   value=value??"";
   if((required && value.Length==0) || value.Length>max)throw new ArgumentException("Invalid field length: "+key);
   foreach(char c in value)if(Char.IsControl(c))throw new ArgumentException("Control character in "+key);
   return value;
  }
  public static List<Room> Parse(string json){
   var serializer=new JavaScriptSerializer {MaxJsonLength=3000000,RecursionLimit=32};
   var root=serializer.DeserializeObject(json) as Dictionary<string,object>;
   if(root==null || !root.ContainsKey("reflectors"))throw new ArgumentException("Missing reflector list");
   var rows=root["reflectors"] as object[];
   if(rows==null || rows.Length==0 || rows.Length>20000)throw new ArgumentException("Invalid reflector list size");
   var result=new List<Room>();
   var seen=new Dictionary<string,Room>(StringComparer.Ordinal);
   foreach(object item in rows){
    var r=item as Dictionary<string,object>;if(r==null)throw new ArgumentException("Invalid reflector record");
    string id=Text(r,"designator",5,true);
    if(!Regex.IsMatch(id,@"\A[0-9]{5}\z"))throw new ArgumentException("Malformed reflector ID; refusing normalization");
    string host=Text(r,"dns",253,false);
    if(host.Length==0)host=Text(r,"ipv4",45,false);
    if(host.Length==0)host=Text(r,"ipv6",45,false);
    if(host.Length==0 || host.Trim()!=host || Uri.CheckHostName(host)==UriHostNameType.Unknown)throw new ArgumentException("Invalid endpoint for "+id);
    object port;if(!r.TryGetValue("port",out port) || !(port is int) || (int)port<1 || (int)port>65535)throw new ArgumentException("Invalid port for "+id);
    var room=new Room {Id=id,Name=Text(r,"name",256,true),Description=Text(r,"description",2048,false),Host=host,Port=(int)port,Country=Text(r,"country",32,false)};
    Room previous;if(seen.TryGetValue(id,out previous)){
     if(previous.Name!=room.Name || previous.Host!=room.Host || previous.Port!=room.Port || previous.Description!=room.Description || previous.Country!=room.Country)throw new ArgumentException("Conflicting duplicate ID: "+id);
     continue;
    }
    seen.Add(id,room);result.Add(room);
   }
   result.Sort(delegate(Room a,Room b){return StringComparer.Ordinal.Compare(a.Id,b.Id);});
   return result;
  }
 }
}
