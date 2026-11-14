using System;
using System.Collections.Generic;
using CumbriaCQ.Offline;
class ReceiveBoundaryTests {
 static int checks;
 static void Check(bool ok,string why){checks++;if(!ok)throw new Exception(why);}
 static byte[] Payload(int n){var p=new byte[65];for(int i=0;i<p.Length;i++)p[i]=(byte)(n*17+i*3);return p;}
 static byte[] Header(string call,int seq,bool end){return YsfWire.Packet("TESTVIA",call,YsfWire.HeaderFrame(call,50,end),seq&127,end);}
 static byte[] Voice(string call,int seq,int marker){return YsfWire.Packet("TESTVIA",call,YsfWire.VoiceFrame(Payload(marker),seq%8,7,50,"TESTCALL"),seq&127,false);}
 static void Collect(BridgeBatch b,long now,List<string> voice,List<long> times){Check(b.Network.Count==0,"Receive must not generate network traffic");foreach(string s in b.Serial){Check(!s.StartsWith("P"),"No physical control output");if(s.StartsWith("D1R")){voice.Add(BitConverter.ToString(VoiceCodec.ParseVoice(s)));times.Add(now);}}}
 static void BackToBack(string next,bool measured){
  var e=new VoiceEngine("TESTGW/WX",50,measured?"D1C000B00005TEST10":"D1C000B00000TEST10","B0 0    0000000",false,measured);
  e.SetConnectedRoom("12345",0);var emitted=new List<string>();var times=new List<long>();
  Collect(e.OnReflector(Header("TESTCALL",0,false),0),0,emitted,times);
  for(int n=1;n<=5;n++){Collect(e.OnReflector(Voice("TESTCALL",n,n),n*100),n*100,emitted,times);Collect(e.Tick(n*100),n*100,emitted,times);}
  Collect(e.OnReflector(Voice("TESTCALL",6,6),510),510,emitted,times);Collect(e.OnReflector(Voice("TESTCALL",7,7),520),520,emitted,times);
  Collect(e.OnReflector(Header("TESTCALL",8,true),530),530,emitted,times);
  for(long t=540;t<=660;t+=10)Collect(e.Tick(t),t,emitted,times);
  Collect(e.OnReflector(Header(next,0,false),665),665,emitted,times);
  for(int n=1;n<=50;n++){long t=700+n*100;for(long tick=t-90;tick<t;tick+=10)Collect(e.Tick(tick),tick,emitted,times);Collect(e.OnReflector(Voice(next,n,n+7),t),t,emitted,times);Collect(e.Tick(t),t,emitted,times);}
  Collect(e.OnReflector(Header(next,51,true),5710),5710,emitted,times);
  for(long t=5720;t<=6300;t+=10)Collect(e.Tick(t),t,emitted,times);
  Check(emitted.Count==57,"Fresh header while prior over drains must preserve all 7 old and 50 new frames; got "+emitted.Count);
  for(int i=0;i<emitted.Count;i++){Check(emitted[i]==BitConverter.ToString(Payload(i+1)),"Ordered encoded bytes must survive handover exactly");if(i>0)Check(times[i]-times[i-1]>=100,"Handover must not produce a catch-up flood");}
  Check(e.DiagnosticCounts["receive-headers"]==2,"Both fresh headers admitted exactly once");
 }
 static int Main(){try{BackToBack("TESTCALL",false);BackToBack("NEXTCALL",true);Console.WriteLine("RECEIVE_BOUNDARY_PASS checks="+checks);return 0;}catch(Exception e){Console.WriteLine("RECEIVE_BOUNDARY_FAIL "+e.Message);return 1;}}
}
