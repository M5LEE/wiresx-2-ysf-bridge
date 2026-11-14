using System;
using System.Collections;
using System.Collections.Generic;
using System.Reflection;
using CumbriaCQ.Offline;
class ReceiveSafetyTests {
 static int checks;
 static void Check(bool ok,string why){checks++;if(!ok)throw new Exception(why);}
 static byte[] Payload(int n){byte[] p=new byte[65];Array.Copy(BitConverter.GetBytes(n),p,4);for(int i=4;i<p.Length;i++)p[i]=(byte)(n*7+i);return p;}
 static byte[] Header(string call,bool end){return YsfWire.Packet("TESTVIA",call,YsfWire.HeaderFrame(call,50,end),end?60:0,end);}
 static byte[] Voice(string call,int seq,int marker){return YsfWire.Packet("TESTVIA",call,YsfWire.VoiceFrame(Payload(marker),seq%8,7,50,"TESTCALL"),seq&127,false);}
 static int Count(VoiceEngine e,string key){int n;return e.DiagnosticCounts.TryGetValue(key,out n)?n:0;}
 static VoiceEngine Started(){var e=new VoiceEngine("TESTGW/WX",50,"D1C000B00005TEST10","B0 0    0000000",false,true);e.SetConnectedRoom("12345",0);e.OnReflector(Header("TESTCALL",false),0);for(int n=1;n<=5;n++){e.OnReflector(Voice("TESTCALL",n,n),n*100);e.Tick(n*100);}return e;}
 static void Bound(VoiceEngine e){
  int n=((ICollection)typeof(VoiceEngine).GetField("received",BindingFlags.NonPublic|BindingFlags.Instance).GetValue(e)).Count;
  object next=typeof(VoiceEngine).GetField("nextReceive",BindingFlags.NonPublic|BindingFlags.Instance).GetValue(e);if(next!=null)n+=((ICollection)next.GetType().GetField("Voice").GetValue(next)).Count;
  Check(n<=4,"Both receive overs together must stay within four queued frames");
  Check(e.DiagnosticCounts["transmit-queue-depth"]<=8,"Outgoing queue remains bounded at eight");
 }
 static void Safety(){
  foreach(string mode in new[]{"stop","room","timeout","wrong-call","wrong-via","backward","huge-jump","corrupt","end-while-paused","header-while-paused","flagged-end-while-paused","native-over"}){
   var e=Started();e.PauseReceive(510);
   if(mode=="stop")e.Stop(600);if(mode=="room")e.SetConnectedRoom("54321",600);
   if(mode=="end-while-paused")e.OnReflector(Header("TESTCALL",true),600);
   if(mode=="header-while-paused")e.OnReflector(Header("TESTCALL",false),600);
   if(mode=="flagged-end-while-paused"){var end=Voice("TESTCALL",7,7);end[34]|=1;e.OnReflector(end,600);}
   long t=mode=="timeout"?4000:1000;e.ResumeReceive(t);
   if(mode=="native-over"){
    e.OnClient("D1F005221016000"+"*****     "+"LOCALCALL "+new string(' ',40)+"09"+new string('0',12),1001);
    e.OnClient(VoiceCodec.SerialVoice("D1E",0,Payload(99)),1002);e.Tick(1002);e.OnClient("P010000",1003);e.Tick(1102);t=1200;
    Check(Count(e,"transmit-voice-admitted")==1,"The intervening native over must genuinely start");
   }
   byte[] p=Voice(mode=="wrong-call"?"OTHERCALL":"TESTCALL",mode=="backward"?4:mode=="huge-jump"?100:10,100);
   if(mode=="wrong-via")Array.Copy(System.Text.Encoding.ASCII.GetBytes("OTHERVIA  "),0,p,4,10);if(mode=="corrupt")p[35]^=1;
   e.OnReflector(p,t);var b=e.Tick(t+100);
   Check(Count(e,"receive-voice-admitted")==5,"A hard boundary or untrusted input cannot resume old speech: "+mode);
   Check(!b.Serial.Exists(delegate(string s){return s.StartsWith("D1R");}),"No stale/fabricated output after "+mode);Bound(e);
  }
  var idle=Started();idle.PauseReceive(510);Check(!idle.CanChangeYsf(2000),"A suspended receive context is not a free endpoint-change boundary");idle.Stop(2001);Check(idle.CanChangeYsf(3001),"Explicit stop frees the endpoint boundary");
  var ended=Started();ended.OnReflector(Header("TESTCALL",true),510);ended.Tick(600);ended.OnReflector(Voice("TESTCALL",10,10),1000);Check(Count(ended,"receive-voice-admitted")==5,"An explicit terminator cannot be treated as a recoverable gap");
  var late=Started();late.Tick(901);late.OnReflector(Voice("TESTCALL",20,20),1600);Check(Count(late,"receive-voice-admitted")==5,"Gaps beyond one second require a new real header");
  var wrap=new VoiceEngine("TESTGW/WX",50,"D1C000B00005TEST10","B0 0    0000000",false,true);wrap.OnReflector(Header("TESTCALL",false),0);wrap.OnReflector(Voice("TESTCALL",125,1),20);wrap.Tick(100);wrap.Tick(421);wrap.OnReflector(Voice("TESTCALL",2,2),500);wrap.Tick(600);Check(Count(wrap,"receive-voice-admitted")==2,"Bounded recovery handles modulo-128 wrap");
 }
 static void Stress(){
  var e=Started();e.Stop(600);var seen=new HashSet<int>();long lastVoice=-1000,now=1000;int id=1000;
  Action<BridgeBatch,long> collect=delegate(BridgeBatch b,long t){foreach(string s in b.Serial){Check(!s.StartsWith("P"),"No physical PTT commands");if(s.StartsWith("D1R")){int value=BitConverter.ToInt32(VoiceCodec.ParseVoice(s),0);Check(value>=1000 && value<id,"Only real supplied voice can be emitted");Check(seen.Add(value),"Never play a frame twice");Check(t-lastVoice>=100,"No catch-up flood during receive stress");lastVoice=t;}}Check(b.Network.Count==0,"Receive stress must not send network speech");Bound(e);};
  for(int call=0;call<200;call++){
   string caller=call%2==0?"TESTCALL":"NEXTCALL";collect(e.OnReflector(Header(caller,false),now),now);
   for(int n=1;n<=24;n++){now+=n%7==0?300:n%5==0?0:100;collect(e.OnReflector(Voice(caller,n,id++),now),now);collect(e.Tick(now),now);if(n%6==0)collect(e.Tick(now),now);}
   collect(e.OnReflector(Header(caller,true),now+1),now+1);now+=20;
   // A following header may arrive before the old queue has drained.
  }
  for(int n=0;n<10;n++){now+=100;collect(e.Tick(now),now);}e.Stop(now);Bound(e);
  Check(seen.Count>1000,"Stress must actually exercise sustained receive playout");
 }
 static int Main(){try{Safety();Stress();Console.WriteLine("RECEIVE_SAFETY_PASS checks="+checks);return 0;}catch(Exception e){Console.WriteLine("RECEIVE_SAFETY_FAIL "+e.Message);return 1;}}
}
