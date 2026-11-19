using System;
using System.IO;
using System.Reflection;
using System.Windows.Forms;
using System.Drawing;
using System.Collections.Generic;
using System.Web.Script.Serialization;
static class LauncherUiTests {
 static int checks;
 static bool startupEnabled=true;
 static void Check(bool ok,string message){if(!ok)throw new Exception(message);checks++;}
 static object Field(object o,string name){return o.GetType().GetField(name,BindingFlags.Instance|BindingFlags.NonPublic).GetValue(o);}
 static string Snapshot(string code){return new JavaScriptSerializer().Serialize(new {Event="Check",Data=new {StatusCode=code,Summary=code=="NeedsAttention"?"The previous session did not finish cleanup, often after a reboot. Close WIRES-X and its YMLAN companion, then select Recover session. Your saved setup will be kept.":"Synthetic status test; no radio actions.",NativeRoom=code=="Running"?"12345":null,YsfDestination="00001 TEST ROOM",CanStart=code=="Stopped",CanStop=code=="Running",CanRecover=code=="NeedsAttention",StartupEnabled=startupEnabled,StartupState=startupEnabled?"Enabled":"Disabled",StartupMessage="Synthetic startup state"}});}
 [STAThread] static int Main(string[] args){
  Application.EnableVisualStyles();Application.SetCompatibleTextRenderingDefault(false);var result=new Dictionary<string,object>();
  try{
   string bin=Path.GetFullPath(args[0]),outDir=Path.GetFullPath(args[1]);Directory.CreateDirectory(outDir);
   var type=Assembly.LoadFrom(Path.Combine(bin,"Bridge.exe")).GetType("LauncherForm");
   var ctor=type.GetConstructor(new[]{typeof(string),typeof(bool),typeof(Func<string>),typeof(Action<string>),typeof(Func<string,string>)});
   Check(ctor!=null,"Alpha.8 launcher must support isolated tray/autostart UI tests");
   int starts=0,stops=0,recoveries=0,startupChanges=0;string snapshot=Snapshot("Stopped");
   Func<string> provider=delegate{return snapshot;};Action<string> action=delegate(string name){if(name=="Start")starts++;else if(name=="Stop")stops++;else if(name=="Recover")recoveries++;else throw new Exception("Unknown injected action");};
   Func<string,string> startup=delegate(string name){startupChanges++;startupEnabled=name=="Enable";return new JavaScriptSerializer().Serialize(new {Enabled=startupEnabled,State=startupEnabled?"Enabled":"Disabled",Message="Synthetic success"});};
   var form=(Form)ctor.Invoke(new object[]{bin,true,provider,action,startup});int step=0,ticks=0;Exception failure=null;var timer=new Timer {Interval=250};
   timer.Tick+=delegate{
    try{
     if(++ticks>100)throw new Exception("UI test timed out at step "+step);
     if(step==0 && starts==1){Check(((NotifyIcon)Field(form,"tray")).Visible,"Tray icon must remain visible during automatic start");Check(!form.Visible,"Automatic sign-in start should initially use the tray");snapshot=Snapshot("Running");type.GetMethod("CheckStatus",BindingFlags.Instance|BindingFlags.NonPublic).Invoke(form,null);step=1;}
     else if(step==1 && ((Label)Field(form,"headline")).Text=="Running"){
      Check(type.GetField("recover",BindingFlags.Instance|BindingFlags.NonPublic)!=null,"Launcher needs a visible guided recovery action");
      foreach(Control control in form.Controls)Check(control.Bounds.Bottom<=form.ClientSize.Height,"Main layout must fit the client area");
      Check(form.Text.Contains("Running"),"Taskbar title must show running state");Check(((TextBox)Field(form,"output")).Text.Contains("12345"),"Status panel must show the current native room");
      Check(((NotifyIcon)Field(form,"tray")).Text.Contains("Running"),"Tray tooltip must report running state");
      form.Close();Check(!form.IsDisposed && !form.Visible,"Window close must hide to tray without stopping the bridge");
      ((ToolStripMenuItem)Field(form,"openItem")).PerformClick();Check(form.Visible,"Tray Open must restore the status window");
      Check(type.GetField("setup",BindingFlags.Instance|BindingFlags.NonPublic)!=null,"Numbered setup action must be available");
      var one=(Button)Field(form,"setup");var two=(Button)Field(form,"check");var three=(Button)Field(form,"start");
      Check(one.Text=="1. Set up bridge" && two.Text=="2. Check status" && three.Text=="3. Start bridge","Main buttons use a clear numbered sequence");
      Check(one.PointToScreen(Point.Empty).Y<two.PointToScreen(Point.Empty).Y && two.PointToScreen(Point.Empty).Y<three.PointToScreen(Point.Empty).Y,"Numbered actions read from top to bottom");
      ((CheckBox)Field(form,"startupBox")).Checked=false;step=2;
     }else if(step==2 && startupChanges==1){
      Check(starts==1 && stops==0,"Status refresh and startup setting must not start twice or stop a session");
      snapshot=Snapshot("Degraded");type.GetMethod("CheckStatus",BindingFlags.Instance|BindingFlags.NonPublic).Invoke(form,null);step=3;
     }else if(step==3 && ((Label)Field(form,"headline")).Text=="Degraded"){
      Check(((NotifyIcon)Field(form,"tray")).Text.Contains("Degraded"),"Degraded link must not retain green running status");
      using(var image=new Bitmap(form.Width,form.Height)){form.DrawToBitmap(image,new Rectangle(0,0,image.Width,image.Height));image.Save(Path.Combine(outDir,"launcher-alpha8.png"));}
      snapshot=Snapshot("NeedsAttention");type.GetMethod("CheckStatus",BindingFlags.Instance|BindingFlags.NonPublic).Invoke(form,null);step=4;
     }else if(step==4 && ((Label)Field(form,"headline")).Text=="Needs attention"){
      var recovery=(Button)Field(form,"recover");Check(recovery.Visible && recovery.Enabled,"Interrupted session offers recovery without enabling Start");
      Check(!((Button)Field(form,"start")).Enabled,"Recovery must not implicitly start the bridge");
      var message=(Label)Field(form,"summary");Check(message.GetPreferredSize(new Size(message.Width,0)).Height<=message.Height,"Full recovery instructions fit without clipping");
      var advice=(Label)Field(form,"nextSteps");Check(advice.Visible && advice.Text.Contains("What to do next") && advice.Text.Contains("Recover session"),"Recovery shows recommended next steps without technical knowledge");
      Check(advice.GetPreferredSize(new Size(advice.Width,0)).Height<=advice.Height,"Recommended fixes fit without clipping");
      using(var image=new Bitmap(form.Width,form.Height)){form.DrawToBitmap(image,new Rectangle(0,0,image.Width,image.Height));image.Save(Path.Combine(outDir,"recovery-preview.png"));}
      recovery.PerformClick();Check(recoveries==1 && starts==1 && stops==0,"Recovery invokes only the explicit recovery action");
      string guidance=(string)type.GetMethod("ExplainActionError",BindingFlags.Static|BindingFlags.NonPublic).Invoke(null,new object[]{"CloseWiresXBeforeRecovery"});Check(guidance.Contains("Close WIRES-X") && guidance.Contains("Recover session"),"Backend refusal gives an actionable explanation");
      timer.Stop();type.GetField("allowClose",BindingFlags.Instance|BindingFlags.NonPublic).SetValue(form,true);form.Close();
     }
    }catch(Exception e){failure=e;timer.Stop();type.GetField("allowClose",BindingFlags.Instance|BindingFlags.NonPublic).SetValue(form,true);form.Close();}
   };timer.Start();Application.Run(form);timer.Dispose();if(failure!=null)throw failure;
   int foreignStarts=0;var foreign=(Form)ctor.Invoke(new object[]{bin,true,new Func<string>(delegate{return Snapshot("OtherSession");}),new Action<string>(delegate{foreignStarts++;}),startup});
   bool foreignControls=false;var finish=new Timer {Interval=1000};finish.Tick+=delegate{finish.Stop();foreignControls=!((Button)Field(foreign,"start")).Enabled && !((Button)Field(foreign,"stop")).Enabled;type.GetField("allowClose",BindingFlags.Instance|BindingFlags.NonPublic).SetValue(foreign,true);foreign.Close();};finish.Start();Application.Run(foreign);finish.Dispose();
   Check(foreignStarts==0,"Automatic start must not take over another bridge installation");Check(foreignControls,"Foreign session controls must remain disabled");
   startupEnabled=false;int unarmedStarts=0;var unarmed=(Form)ctor.Invoke(new object[]{bin,true,new Func<string>(delegate{return Snapshot("Stopped");}),new Action<string>(delegate{unarmedStarts++;}),startup});
   var end=new Timer {Interval=1000};end.Tick+=delegate{end.Stop();type.GetField("allowClose",BindingFlags.Instance|BindingFlags.NonPublic).SetValue(unarmed,true);unarmed.Close();};end.Start();Application.Run(unarmed);end.Dispose();Check(unarmedStarts==0,"Automatic entry must not start unless sign-in startup is explicitly enabled and verified");
   result["Pass"]=true;result["Assertions"]=checks;result["HardwareActions"]=0;result["StartupChangesInjected"]=true;
  }catch(Exception e){result["Pass"]=false;result["Error"]=e.ToString();}
  Console.WriteLine(new JavaScriptSerializer().Serialize(result));return Object.Equals(result["Pass"],true)?0:1;
 }
}
