using System;
using System.Collections.Generic;
using CumbriaCQ.Offline;
class ReceiveRecoveryTests {
 static int checks;
 static void Check(bool ok,string why){checks++;if(!ok)throw new Exception(why);}
 static byte[] Payload(int n){byte[] p=new byte[65];for(int i=0;i<p.Length;i++)p[i]=(byte)(n*13+i);return p;}
 static byte[] Header(string caller,bool end){return YsfWire.Packet("TESTVIA",caller,YsfWire.HeaderFrame(caller,50,end),end?60:0,end);}
 static byte[] Voice(string caller,int seq,int marker){return YsfWire.Packet("TESTVIA",caller,YsfWire.VoiceFrame(Payload(marker),seq%8,7,50,"TESTCALL"),seq&127,false);}
 static int Count(VoiceEngine e,string key){int n;return e.DiagnosticCounts.TryGetValue(key,out n)?n:0;}
 static VoiceEngine Started(){var e=new VoiceEngine("TESTGW/WX",50,"D1C000B00005TEST10","B0 0    0000000",false,true);e.SetConnectedRoom("12345",0);e.OnReflector(Header("TESTCALL",false),0);for(int n=1;n<=5;n++){e.OnReflector(Voice("TESTCALL",n,n),n*100);e.Tick(n*100);}return e;}
 static BridgeBatch Pause(VoiceEngine e,long now){var m=typeof(VoiceEngine).GetMethod("PauseReceive");return m==null?e.Stop(now):(BridgeBatch)m.Invoke(e,new object[]{now});}
 static void Resume(VoiceEngine e,long now){var m=typeof(VoiceEngine).GetMethod("ResumeReceive");if(m!=null)m.Invoke(e,new object[]{now});}
 static void ProofPause(){
  var e=Started();Pause(e,510);Check(e.Tick(600).Serial.Count==0,"No queued audio while proof is unavailable");Resume(e,2510);
  e.OnReflector(Voice("TESTCALL",26,26),2600);var b=e.Tick(2700);
  Check(Count(e,"receive-voice-admitted")==6,"Freshly reverified same-stream traffic should recover after a bounded proof pause");
  string voice=b.Serial.Find(delegate(string s){return s.StartsWith("D1R");});Check(voice!=null && BitConverter.ToString(VoiceCodec.ParseVoice(voice))==BitConverter.ToString(Payload(26)),"Recovery emits only the real resumed frame, never old or filler audio");
  Check(b.Serial.Exists(delegate(string s){return s.StartsWith("D1H") && s.Contains("TESTCALL");}),"Recovery reestablishes validated source metadata before speech");
 }
 static void Gap(bool schedulerRuns){
  var e=Started();if(schedulerRuns)e.Tick(901);
  e.OnReflector(Voice("TESTCALL",10,10),1000);var b=e.Tick(1100);
  Check(Count(e,"receive-voice-admitted")==6,"A 500ms same-stream gap must not reject the rest of the over (scheduler="+schedulerRuns+")");
  string frame=b.Serial.Find(delegate(string s){return s.StartsWith("D1R");});
  Check(frame!=null && BitConverter.ToString(VoiceCodec.ParseVoice(frame))==BitConverter.ToString(Payload(10)),"Gap recovery must contain only the genuine resumed frame");
  Check(e.Tick(1100).Serial.Count==0,"Recovery must not emit twice at the same instant");
  for(int n=11;n<=30;n++){e.OnReflector(Voice("TESTCALL",n,n),n*100);e.Tick(n*100+100);}
  Check(Count(e,"receive-voice-admitted")==26,"A recovered gap must not poison subsequent sequence admission");
 }
 static void SequenceAndOverflow(){
  var e=Started();e.OnReflector(Voice("TESTCALL",10,10),800);var b=e.Tick(900);
  Check(Count(e,"receive-voice-admitted")==6 && b.Serial.Exists(delegate(string s){return s.StartsWith("D1R");}),"A bounded forward jump consistent with elapsed time must recover before idle expiry");
  e.OnReflector(Voice("TESTCALL",9,9),910);Check(Count(e,"receive-voice-admitted")==6,"Backward/out-of-order packets remain rejected");
  e.OnReflector(Voice("TESTCALL",11,11),1000);Check(Count(e,"receive-voice-admitted")==7,"A bounded jump must establish the next genuine sequence");
  var q=new VoiceEngine("TESTGW/WX",50,"D1C000B00005TEST10","B0 0    0000000",false,true);q.OnReflector(Header("TESTCALL",false),0);
  for(int n=1;n<=12;n++)q.OnReflector(Voice("TESTCALL",n,n),1);
  Check(Count(q,"receive-voice-admitted")==4 && Count(q,"receive-queue-full")==8,"Overflow retains the shared four-frame limit and exact loss accounting");
  q.Tick(100);q.OnReflector(Voice("TESTCALL",13,13),101);
  Check(Count(q,"receive-voice-admitted")==5 && Count(q,"sequence-gap")==0,"Known local queue drops must not poison the next admissible frame's sequence");
 }
 static int Main(){try{ProofPause();Gap(true);Gap(false);SequenceAndOverflow();Console.WriteLine("RECEIVE_RECOVERY_PASS checks="+checks);return 0;}catch(Exception e){Console.WriteLine("RECEIVE_RECOVERY_FAIL "+e.Message);return 1;}}
}
