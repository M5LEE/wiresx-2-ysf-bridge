using System;
using System.Reflection;
using CumbriaCQ.Offline;
class RoomProofTests {
 static int checks;static Type trackerType;
 static void Check(bool ok,string why){checks++;if(!ok)throw new Exception(why);}
 static object Tracker(){trackerType=typeof(VoiceEngine).Assembly.GetType("CumbriaCQ.Offline.RoomProofTracker");Check(trackerType!=null,"Recovery needs a proven log-continuity token, not just room and second-resolution timestamp");return Activator.CreateInstance(trackerType);}
 static string Observe(object tracker,string text,int total,bool partial){var view=new NativeLogView{Text=text,Lines=text.Split('\n').Length-1,Partial=partial};var field=typeof(NativeLogView).GetField("TotalLines");Check(field!=null,"Native observation must retain the bounded tail's absolute line count");field.SetValue(view,total);trackerType.GetMethod("Observe").Invoke(tracker,new object[]{view});return (string)trackerType.GetProperty("ConnectionKey").GetValue(tracker,null);}
 const string Join="2026/01/02 12:00:00 Connected to TEST(12345).\n";
 const string Leave="2026/01/02 12:00:00 Disconnect.\n";
 static void MainChecks(){
  var t=Tracker();string a=Observe(t,Join+"\n",2,false);Check(a!=null,"A fresh structured connection is verified");
  Check(Observe(t,Join+"\n",2,false)==a,"Unchanged successful snapshots preserve continuity");
  // An unavailable read never calls Observe. A later complete overlapping tail is required.
  Check(Observe(t,Join+"2026/01/02 12:00:02 Receiving.\n\n",3,false)==a,"A skipped read followed by continuous same-room log retains its token");
  string b=Observe(t,Join+"2026/01/02 12:00:02 Receiving.\n"+Leave+Join+"\n",5,false);
  Check(b!=a,"Same-second disconnect/reconnect must invalidate the old token even for the same room");
  Check(Observe(t,Join+"\n",2,false)!=b,"Log reset invalidates old continuity");
  var u=Tracker();string c=Observe(u,Join+"\n",2,false);
  Check(Observe(u,"2026/01/02 12:00:05 Receiving.\n\n",300,false)!=c,"A tail with no provable overlap must not authorise resume");
  var v=Tracker();string d=Observe(v,Join+"\n",2,false);bool rejected=false;
  try{Observe(v,Leave+"\n",3,true);}catch(TargetInvocationException){rejected=true;}
  Check(rejected,"Partial log reads cannot publish verified connection state");
  Check(Observe(v,Join+"\n",2,false)==d,"A rejected partial read does not corrupt the prior bounded reference");
  Check(Observe(v,Join+Leave+"\n",3,false)==null,"An explicit disconnect remains disconnected");
  var w=Tracker();Check(Observe(w,Join+"\n",2,false)!=d,"A restarted observer cannot reuse another observer's connection token");
 }
 static int Main(){try{MainChecks();Console.WriteLine("ROOM_PROOF_PASS checks="+checks);return 0;}catch(Exception e){Console.WriteLine("ROOM_PROOF_FAIL "+e.Message);return 1;}}
}
