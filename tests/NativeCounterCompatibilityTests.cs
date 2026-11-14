// Copyright (c) 2026 M5LEE.
// SPDX-License-Identifier: GPL-3.0-or-later
using System;
using System.Collections.Generic;
using CumbriaCQ.Offline;
class NativeCounterCompatibilityTests {
 static int checks;
 static void Check(bool value,string message){if(!value)throw new Exception(message);checks++;}
 static string Header(){return "D1F005221016000"+"*****     "+"TESTCALL  "+new string(' ',40)+"09"+new string('0',12);}
 static byte[] Payload(int index){byte[] p=new byte[65];for(int i=0;i<p.Length;i++)p[i]=(byte)(index*7+i*3);return p;}
 static List<byte[]> Voice(BridgeBatch b){return b.Network.FindAll(delegate(byte[] p){byte[] f=new byte[25];Array.Copy(p,40,f,0,25);return YsfWire.ReadFich(f)[0]==1;});}
 static void PeriodicMarker(){
  var engine=new VoiceEngine("TESTGW/WX",50,"D1C000B00000TEST10","B0 0    0000000",false);engine.OnClient(Header(),0);
  var packets=new List<byte[]>();
  for(int i=0;i<80;i++){
   int wire=i*5+(i%8==7?1:0);packets.AddRange(Voice(engine.OnClient(VoiceCodec.SerialVoice("D1E",wire,Payload(i)),i*100)));packets.AddRange(Voice(engine.Tick(i*100)));
  }
  Console.WriteLine("PeriodicMarker input=80 output="+packets.Count);
  Check(packets.Count==80,"Periodic native counter marker must not drop one voice frame in eight");
  for(int i=0;i<packets.Count;i++)Check(BitConverter.ToString(YsfWire.ReceiveVoice(packets[i],50,false))==BitConverter.ToString(Payload(i)),"Marker compatibility must preserve every encoded voice byte and order");
  Check(!engine.DiagnosticCounts.ContainsKey("transmit-sequence-rejected") && !engine.DiagnosticCounts.ContainsKey("transmit-frames-missing"),"A recognised native counter marker must not be reported as lost speech");
 }
 static VoiceEngine Engine(){var e=new VoiceEngine("TESTGW/WX",50,"D1C000B00000TEST10","B0 0    0000000",false);e.OnClient(Header(),0);return e;}
 static void NominalOriginsAndWrap(){
  foreach(int origin in new[]{0,1,2,3,4,36,65500,65520,65530}){
   var e=Engine();var packets=new List<byte[]>();
   for(int i=0;i<80;i++){packets.AddRange(Voice(e.OnClient(VoiceCodec.SerialVoice("D1E",(origin+i*5)&65535,Payload(i)),i*100)));packets.AddRange(Voice(e.Tick(i*100)));}
   Check(packets.Count==80,"Nominal counters must remain valid at every initial phase and wrap");
   for(int i=0;i<packets.Count;i++)Check(BitConverter.ToString(YsfWire.ReceiveVoice(packets[i],50,false))==BitConverter.ToString(Payload(i)),"Nominal counter compatibility must be byte exact");
   Check(!e.DiagnosticCounts.ContainsKey("transmit-native-cycle-marker"),"A nominal counter ending36 must not be rewritten");
  }
 }
 static void DuplicateAndConflict(){
  var e=Engine();
  for(int i=0;i<8;i++){e.OnClient(VoiceCodec.SerialVoice("D1E",i==7?36:i*5,Payload(i)),i*100);e.Tick(i*100);}
  e.OnClient(VoiceCodec.SerialVoice("D1E",36,Payload(7)),710);
  e.OnClient(VoiceCodec.SerialVoice("D1E",35,Payload(7)),711);
  Check(e.DiagnosticCounts["transmit-duplicate"]==2 && Voice(e.Tick(711)).Count==0,"Marked and ordinary aliases must not replay the same payload");
  e.OnClient(VoiceCodec.SerialVoice("D1E",36,Payload(99)),712);
  Check(e.DiagnosticCounts["transmit-sequence-rejected"]==1 && Voice(e.Tick(712)).Count==0,"A conflicting old logical counter must remain rejected");
  e.OnClient(VoiceCodec.SerialVoice("D1E",40,Payload(8)),800);
  Check(Voice(e.Tick(800)).Count==1,"A recognised marker must not shift the next counter phase");
 }
 static void BoundsAndMissing(){
  var invalid=Engine();invalid.OnClient(VoiceCodec.SerialVoice("D1E",0,Payload(0)),0);invalid.Tick(0);
  invalid.OnClient(VoiceCodec.SerialVoice("D1E",36,Payload(1)),100);
  invalid.OnClient(VoiceCodec.SerialVoice("D1E",6,Payload(1)),101);
  Check(invalid.DiagnosticCounts["transmit-sequence-rejected"]==2 && Voice(invalid.Tick(101)).Count==0,"Unknown large jumps and unrelated plus-one offsets must remain rejected");
  invalid.OnClient(VoiceCodec.SerialVoice("D1E",5,Payload(1)),200);Check(Voice(invalid.Tick(200)).Count==1,"Rejected offsets must not poison valid continuation");
  var missing=Engine();missing.OnClient(VoiceCodec.SerialVoice("D1E",25,Payload(0)),0);missing.Tick(0);
  missing.OnClient(VoiceCodec.SerialVoice("D1E",36,Payload(1)),200);
  Check(Voice(missing.Tick(200)).Count==1 && missing.DiagnosticCounts["transmit-frames-missing"]==1,"A genuine missing slot before a marked slot must be counted exactly once");
  var nearWrap=Engine();var packets=new List<byte[]>();
  for(int i=0;i<16;i++){int n=(65500+i*5)&65535,wire=n%40==35?n+1:n;packets.AddRange(Voice(nearWrap.OnClient(VoiceCodec.SerialVoice("D1E",wire,Payload(i)),i*100)));packets.AddRange(Voice(nearWrap.Tick(i*100)));}
  Check(packets.Count==16 && nearWrap.DiagnosticCounts["transmit-native-cycle-marker"]==1,"The supported marker and following native wrap must preserve the logical phase");
  nearWrap.Stop(1600);Check(nearWrap.OnClient(VoiceCodec.SerialVoice("D1E",36,Payload(2)),1700).Network.Count==0,"Stop must clear marker history and still require fresh metadata");
 }
 static int Main(){try{PeriodicMarker();NominalOriginsAndWrap();DuplicateAndConflict();BoundsAndMissing();Console.WriteLine("NATIVE_COUNTER_COMPATIBILITY_PASS checks="+checks);return 0;}catch(Exception e){Console.Error.WriteLine("NATIVE_COUNTER_COMPATIBILITY_FAIL "+e.Message);return 1;}}
}
