using System;
using System.Collections.Generic;
using System.Text;
using CumbriaCQ.Offline;
class CallsignMetadataTests {
 static readonly byte[] White={0x93,0xD7,0x51,0x21,0x9C,0x2F,0x6C,0xD0,0xEF,0x0F,0xF8,0x3D,0xF1,0x73,0x20,0x94,0xED,0x1E,0x7C,0xD8};
 static int Bit(byte[] b,int i){return (b[i/8]>>(7-i%8))&1;}
 static string Decode(byte[] p,int size,int offset){
  int chunk=size==10?5:9,steps=size==10?100:180,columns=size==10?5:9;byte[] enc=new byte[chunk*5];for(int i=0;i<5;i++)Array.Copy(p,offset+i*18,enc,i*chunk,chunk);
  byte[] raw=new byte[size+3];int d1=0,d2=0,d3=0,d4=0;for(int i=0;i<steps;i++){int n=i/columns*2+i%columns*40;int d=Bit(enc,n)^d3^d4;if(Bit(enc,n+1)!=(d^d1^d2^d4))throw new Exception("Data FEC invalid");if(d!=0)raw[i/8]|=(byte)(0x80>>(i%8));d4=d3;d3=d2;d2=d1;d1=d;}
  int crc=0;for(int i=0;i<size;i++){crc^=raw[i]<<8;for(int b=0;b<8;b++)crc=((crc<<1)^((crc&32768)!=0?0x1021:0))&65535;}crc=(~crc)&65535;if(raw[size]!=(byte)(crc>>8) || raw[size+1]!=(byte)crc)throw new Exception("Data CRC invalid");for(int i=0;i<size;i++)raw[i]^=White[i];return Encoding.ASCII.GetString(raw,0,size);
 }
 static List<byte[]> Stream(){var e=new VoiceEngine("TESTGW/WX",50,"D1C000B00000TEST10","B0 0    0000000",false);var packets=new List<byte[]>();e.OnClient("D1F005220016000"+"*****     "+"TESTCALL  "+new string(' ',40)+"09"+new string('0',12),0);for(int i=0;i<16;i++){packets.AddRange(e.OnClient(VoiceCodec.SerialVoice("D1E",i*5,new byte[65]),i*100).Network);packets.AddRange(e.Tick(i*100).Network);}e.OnClient("P010000",1600);packets.AddRange(e.Tick(1600).Network);return packets;}
 static int Main(){try{var packets=Stream();int voices=0,headers=0;foreach(var p in packets){byte[] fich=new byte[25];Array.Copy(p,40,fich,0,25);int[] f=YsfWire.ReadFich(fich);
  if(f[0]==0 || f[0]==2){if(Decode(p,20,65)!="**********TESTCALL  ")throw new Exception("Header source changed");if(Decode(p,20,74)!="TESTGW/WX           ")throw new Exception("Header downlink is blank/inconsistent with periodic FN2 callsign");headers++;continue;}
  if(f[0]!=1)continue;int fn=f[1];string actual=Decode(p,10,65);string expected=(fn==0?"**********":fn==1?"TESTCALL":fn==2?"TESTGW/WX":"").PadRight(10);if(actual!=expected)throw new Exception("Yaesu table4-4 FN"+fn+" has incorrect role: ID/remarks slots must not contain gateway callsigns");foreach(byte b in VoiceCodec.GetVoice(p))if(b!=0)throw new Exception("Voice bytes changed");voices++;}if(voices!=16 || headers!=2)throw new Exception("Incomplete synthetic over");Console.WriteLine("CALLSIGN_METADATA_PASS voice_frames="+voices+" headers="+headers+" source_and_slot_roles_valid=true voice_unchanged=true");return 0;}catch(Exception e){Console.WriteLine(e.Message);return 1;}}
}
