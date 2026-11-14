using System;
using System.Collections.Generic;
using System.Security.Cryptography;
using System.Text;
using CumbriaCQ.Offline;
class ReceiveTraceTests {
 static readonly List<string> rows=new List<string>();static int serialVoice,networkVoice;
 static byte[] Payload(int n,bool alter){var p=new byte[65];for(int i=0;i<p.Length;i++)p[i]=(byte)(n*17+i*3);if(alter)p[0]^=1;return p;}
 static void Capture(BridgeBatch batch,long now){foreach(string s in batch.Serial){if(s.StartsWith("P"))throw new Exception("PhysicalControl");rows.Add(now+" S "+s);if(s.StartsWith("D1R"))serialVoice++;}foreach(byte[] p in batch.Network){rows.Add(now+" N "+BitConverter.ToString(p));byte[] f=new byte[25];Array.Copy(p,40,f,0,25);if(YsfWire.ReadFich(f)[0]==1)networkVoice++;}}
 static void Run(bool measured,bool alter){
  for(int direction=0;direction<2;direction++){
   var e=new VoiceEngine("TESTGW/WX",50,measured?"D1C000B00005TEST10":"D1C000B00000TEST10","B0 0    0000000",false,measured);
   Capture(e.SetConnectedRoom("12345",0),0);
   for(int over=0;over<3;over++){
    long start=over*20000;string call=over%2==0?"TESTCALL":"NEXTCALL";
    if(direction==0)Capture(e.OnReflector(YsfWire.Packet("TESTVIA",call,YsfWire.HeaderFrame(call,50,false),0,false),start),start);
    else Capture(e.OnClient("D1F005221016000"+"*****     "+call.PadRight(10)+new string(' ',40)+"09"+new string('0',12),start),start);
    for(int n=1;n<=150;n++){
     long t=start+n*100;byte[] voice=Payload(n,alter);
     if(direction==0)Capture(e.OnReflector(YsfWire.Packet("TESTVIA",call,YsfWire.VoiceFrame(voice,n%8,7,50,"TESTCALL"),n&127,false),t),t);
     else Capture(e.OnClient(VoiceCodec.SerialVoice("D1E",(n-1)*5,voice),t),t);
     Capture(e.Tick(t),t);Capture(e.OnClient("D1C0000",t+1),t+1);Capture(e.Tick(t+10),t+10);
    }
    long end=start+15010;
    if(direction==0)Capture(e.OnReflector(YsfWire.Packet("TESTVIA",call,YsfWire.HeaderFrame(call,50,true),151&127,true),end),end);
    else Capture(e.OnClient("P010000",end),end);
    for(long t=end+10;t<=end+600;t+=10)Capture(e.Tick(t),t);
   }
  }
 }
 static int Main(string[] args){try{bool alter=args.Length==1 && args[0]=="--alter";Run(false,alter);Run(true,alter);if(serialVoice!=900 || networkVoice!=900)throw new Exception("HealthyTraceVoiceCount");string hash;using(var sha=SHA256.Create())hash=BitConverter.ToString(sha.ComputeHash(Encoding.UTF8.GetBytes(string.Join("\n",rows.ToArray())))).Replace("-","");Console.WriteLine("{\"Pass\":true,\"Events\":"+rows.Count+",\"SerialVoice\":"+serialVoice+",\"NetworkVoice\":"+networkVoice+",\"Sha256\":\""+hash+"\"}");return 0;}catch(Exception e){Console.WriteLine("RECEIVE_TRACE_FAIL "+e.Message);return 1;}}
}
