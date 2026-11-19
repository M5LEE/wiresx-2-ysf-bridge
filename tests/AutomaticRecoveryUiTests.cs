using System;
using System.IO;
using System.Reflection;
using System.Windows.Forms;
using System.Collections.Generic;
using System.Web.Script.Serialization;
static class AutomaticRecoveryUiTests {
 static Type type; static int checks; static string bin;
 static void Check(bool ok,string message){if(!ok)throw new Exception(message);checks++;}
 static string Snapshot(string code,bool enabled){return new JavaScriptSerializer().Serialize(new {Event="Check",Data=new {StatusCode=code,Summary="Isolated recovery test",CanStart=code=="Stopped",CanStop=false,CanRecover=code=="NeedsAttention",StartupEnabled=enabled,StartupState=enabled?"Enabled":"Disabled"}});}
 static void Invoke(Form form,string name,params object[] args){type.GetMethod(name,BindingFlags.Instance|BindingFlags.NonPublic).Invoke(form,args);}
 static void Scenario(string initial,bool enabled,bool success){
  string state=initial;var actions=new List<string>();int ticks=0;Exception failure=null;bool completed=false;
  var ctor=type.GetConstructor(new[]{typeof(string),typeof(bool),typeof(Func<string>),typeof(Action<string>),typeof(Func<string,string>)});
  var form=(Form)ctor.Invoke(new object[]{bin,true,new Func<string>(delegate{return Snapshot(state,enabled);}),new Action<string>(delegate(string a){actions.Add(a);}),new Func<string,string>(delegate{return "{}";})});
  var timer=new Timer {Interval=100};
  timer.Tick+=delegate{
   try{
    ticks++;
    if(initial=="NeedsAttention" && enabled){
     if(ticks==15)Check(actions.Count==1 && actions[0]=="Recover","Enabled automatic startup must recover an interrupted session without a button click");
     if(ticks==16){Invoke(form,"CheckStatus");}
     if(ticks==20){Check(actions.Count==1,"Do not repeat recovery or start before recovery completes");state=success?"Stopped":"NeedsAttention";Invoke(form,"CompleteAction","Recover",success?0:1,"RecoveryAliasChanged");completed=true;}
     if(ticks==30){Check(completed && actions.Count==(success?2:1),"Only a successful recovery may continue to Start");if(success)Check(actions[1]=="Start","Recovery must continue to Start automatically");Invoke(form,"CheckStatus");}
     if(ticks==40)Check(actions.Count==(success?2:1),"Status polling must never loop recovery or duplicate Start");
    }else if(ticks==30)Check(actions.Count==0,"Disabled startup and foreign/live sessions must not recover or start");
    if(ticks>=40){timer.Stop();type.GetField("allowClose",BindingFlags.Instance|BindingFlags.NonPublic).SetValue(form,true);form.Close();}
   }catch(Exception e){failure=e;timer.Stop();type.GetField("allowClose",BindingFlags.Instance|BindingFlags.NonPublic).SetValue(form,true);form.Close();}
  };
  timer.Start();Application.Run(form);timer.Dispose();if(failure!=null)throw failure;
 }
 [STAThread] static int Main(string[] args){
  try{Application.EnableVisualStyles();bin=args[0];type=Assembly.LoadFrom(Path.Combine(bin,"Bridge.exe")).GetType("LauncherForm");Scenario("NeedsAttention",true,true);Scenario("NeedsAttention",true,false);Scenario("NeedsAttention",false,false);Scenario("OtherSession",true,false);Scenario("Running",true,false);Console.WriteLine("AUTOMATIC_RECOVERY_UI_PASS checks="+checks);return 0;}catch(Exception e){Console.WriteLine(e.ToString());return 1;}
 }
}
