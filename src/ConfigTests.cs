using System;
using System.IO;
using CumbriaCQ.Configuration;
class ConfigTests {
 static int checks;
 static void Check(bool pass,string name){if(!pass)throw new Exception("FAIL: "+name);checks++;Console.WriteLine("PASS: "+name);}
 static void Reject(Action action,string name){bool rejected=false;try{action();}catch(ArgumentException){rejected=true;}Check(rejected,name);}
 static int Main(){try{
  var s=SettingsStore.Defaults();
  Check(s.SchemaVersion==1 && s.YsfRoomId=="23534" && s.YsfRoomName=="CUMBRIACQ" && s.YsfHost=="57.128.190.202" && s.YsfPort==42100 && s.DgId==50 && s.AllowZeroDg,"missing config preserves the actual current bridge target and DG-ID policy");
  string dir=Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"config-test-"+Guid.NewGuid().ToString("N"));Directory.CreateDirectory(dir);
  try{
   string path=Path.Combine(dir,"bridge-config.json");var initial=SettingsStore.Open(path);
   s.YsfRoomId="00041";s.YsfRoomName="Full selected room name";s.YsfHost="example.invalid";s.YsfPort=42000;s.DgId=0;s.AllowZeroDg=false;
   SettingsStore.Save(path,s,initial.Fingerprint);
   Check(File.Exists(path),"saving selected reflector creates the configuration file");
   var loaded=SettingsStore.Open(path);Check(loaded.Settings.YsfRoomId=="00041" && loaded.Settings.YsfRoomName==s.YsfRoomName && loaded.Settings.YsfHost==s.YsfHost && loaded.Settings.YsfPort==42000 && loaded.Settings.DgId==0 && !loaded.Settings.AllowZeroDg,"saved endpoint and exact leading-zero ID survive reopen");
   string original=File.ReadAllText(path);s.DgId=1;string backup=SettingsStore.Save(path,s,loaded.Fingerprint);
   Check(File.Exists(backup) && File.ReadAllText(backup)==original,"replacement keeps an exact backup of the prior configuration");
   string current=File.ReadAllText(path);bool rejected=false;try{SettingsStore.Save(path,s,loaded.Fingerprint);}catch(IOException){rejected=true;}
   Check(rejected && File.ReadAllText(path)==current,"stale editor cannot overwrite a changed configuration");
   File.WriteAllText(path,current.Replace("\"SchemaVersion\":1","\"FutureSetting\":\"keep me\",\"SchemaVersion\":1"));var extended=SettingsStore.Open(path);s.DgId=2;SettingsStore.Save(path,s,extended.Fingerprint);
   Check(File.ReadAllText(path).Contains("\"FutureSetting\":\"keep me\""),"editing reflector settings preserves unrelated configuration fields");
   Check(Directory.GetFiles(dir,"*.pending").Length==0,"atomic settings publication leaves no pending files");
   var bad=SettingsStore.Defaults();bad.YsfRoomId="41";Reject(delegate{SettingsStore.Save(path,bad,SettingsStore.Open(path).Fingerprint);},"malformed YSF ID is rejected rather than padded");
   bad=SettingsStore.Defaults();bad.YsfHost="https://example.invalid/path";Reject(delegate{SettingsStore.Validate(bad);},"URLs are not accepted as reflector endpoint hosts");
   bad=SettingsStore.Defaults();bad.YsfPort=0;Reject(delegate{SettingsStore.Validate(bad);},"zero UDP port is refused");
   bad=SettingsStore.Defaults();bad.DgId=128;Reject(delegate{SettingsStore.Validate(bad);},"DG-ID outside seven-bit range is refused");
   bad=SettingsStore.Defaults();bad.SchemaVersion=2;Reject(delegate{SettingsStore.Validate(bad);},"unknown configuration schema is not silently rewritten");
   string cache=Path.Combine(dir,"catalog.json");
   CumbriaCQ.Catalog.Catalog.Publish("{\"reflectors\":[{\"designator\":\"00041\",\"name\":\"Full selected room name\",\"description\":\"West coast network\",\"dns\":\"example.invalid\",\"port\":42100,\"country\":\"GB\"}]}",cache,1,"");
   var catalog=CatalogView.Load(cache);Check(catalog.Rooms.Count==1 && catalog.Rooms[0].Id=="00041" && catalog.Rooms[0].Name=="Full selected room name" && catalog.FetchedAtUtc.Kind==DateTimeKind.Utc,"editor loads the existing validated catalogue cache without losing leading zeros or names");
   Check(CatalogView.Filter(catalog.Rooms,"WEST COAST").Count==1 && CatalogView.Filter(catalog.Rooms,"00041").Count==1 && CatalogView.Filter(catalog.Rooms,"unmatched").Count==0,"room search matches ID and full description case-insensitively");
  }finally{Directory.Delete(dir,true);}
  Console.WriteLine("RESULT: "+checks+" configuration checks passed");return 0;
 }catch(Exception e){Console.Error.WriteLine(e.ToString());return 1;}}
}
