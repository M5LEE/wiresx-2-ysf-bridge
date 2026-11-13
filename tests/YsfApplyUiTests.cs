using System;
using System.IO;
using System.Reflection;
using System.Diagnostics;
using System.Windows.Forms;
using System.Web.Script.Serialization;
using CumbriaCQ.Configuration;
static class YsfApplyUiTests {
 static int checks;static JavaScriptSerializer json=new JavaScriptSerializer();
 static void Check(bool ok,string why){if(!ok)throw new Exception(why);checks++;}
 static void Put(string path,object value){Directory.CreateDirectory(Path.GetDirectoryName(path));File.WriteAllText(path,json.Serialize(value));}
 static Control Find(Control c,string text){if(c is Button && c.Text==text)return c;foreach(Control child in c.Controls){var found=Find(child,text);if(found!=null)return found;}return null;}
 [STAThread] static int Main(string[] args){Form form=null;try{
  string bin=Path.GetFullPath(args[0]),root=Path.GetFullPath(args[1]);Directory.CreateDirectory(root);string app=AppDomain.CurrentDomain.BaseDirectory.TrimEnd(Path.DirectorySeparatorChar);
  Directory.CreateDirectory(Path.Combine(app,"assets"));if(!String.Equals(app,bin,StringComparison.OrdinalIgnoreCase))File.Copy(Path.Combine(bin,"assets","settings.ico"),Path.Combine(app,"assets","settings.ico"),true);
  var s=SettingsStore.Defaults();SettingsStore.Save(Path.Combine(root,"bridge-config.json"),s,"MISSING");
  Put(Path.Combine(root,"room-cache","catalog.json"),new {SchemaVersion=1,SourceUrl=CumbriaCQ.Catalog.Catalog.SourceUrl,Count=2,FetchedAtUtc=DateTime.UtcNow.ToString("o"),Rooms=new[]{new {Id="23534",Name="CUMBRIACQ",Host=s.YsfHost,Port=s.YsfPort,Country="GB",Description="Fixture"},new {Id="00016",Name="MARRAS",Host="127.0.0.1",Port=42201,Country="GB",Description="Fixture"}}});
  var p=Process.GetCurrentProcess();string tag="bridge"+new string('c',32),start=p.StartTime.ToUniversalTime().ToString("o");Put(Path.Combine(root,"launcher-state","owner.json"),new {Root=root,Tag=tag,State="Running",Adapter=new {Pid=p.Id,Created=start,Root=root,Tag=tag}});Put(Path.Combine(root,"progress-"+tag+".json"),new {Tag=tag,AdapterPid=p.Id,AdapterStartUtc=start,YsfApplyVersion=1,YsfProgramRoot=app,YsfActive=s,YsfApply=new {RequestId="",State="Idle",Message="Fixture"}});
  var a=Assembly.LoadFrom(Path.Combine(bin,"Bridge.exe"));var t=a.GetType("ConfigForm",true);form=(Form)Activator.CreateInstance(t,new object[]{root,Path.Combine(root,"bridge-config.json"),null});
  var apply=Find(form,"Apply YSF room") as Button;Check(apply!=null,"The configuration window must offer Apply YSF room without Stop/Start");form.Show();Application.DoEvents();var list=(ListView)t.GetField("list",BindingFlags.Instance|BindingFlags.NonPublic).GetValue(form);
  foreach(ListViewItem item in list.Items){item.Selected=item.Text=="00016";}Application.DoEvents();Check(apply.Enabled,"A selected target must enable live apply");apply.PerformClick();Application.DoEvents();
  string request=Path.Combine(root,"ysf-apply-"+tag+".json");Check(File.Exists(request),"Clicking Apply must queue the request, not only save settings");Check(SettingsStore.Open(Path.Combine(root,"bridge-config.json")).Settings.YsfRoomId=="00016","Apply must save exactly the selected target");
  var runtime=(Label)t.GetField("runtimeInfo",BindingFlags.Instance|BindingFlags.NonPublic).GetValue(form);Check(runtime.Text.Contains("23534") && !runtime.Text.Contains("Active YSF: 00016"),"The UI must distinguish the old active destination from the newly saved target");
  Console.WriteLine("YSF_APPLY_UI_PASS checks="+checks+" actual_click=true native_restarted=false");return 0;
 }catch(Exception ex){Console.WriteLine(ex.ToString());return 1;}finally{if(form!=null)form.Dispose();}}
}
